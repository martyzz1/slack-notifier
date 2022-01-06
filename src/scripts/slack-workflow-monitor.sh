SlackMonitor() {
    SetupVars
    ValidateWorkflow
    echo CIRCLE_TOKEN "${CIRCLE_TOKEN}"
    echo GIPHY_TOKEN "${GIPHY_TOKEN}"
    echo SLACK_WEBHOOK "${SLACK_WEBHOOK}"
    echo GIPHY_SUCCESS_KEYWORD "${GIPHY_SUCCESS_KEYWORD}"
    echo GIPHY_FAILURE_KEYWORD "${GIPHY_FAILURE_KEYWORD}"
    echo WORKFLOW_NAME "${WORKFLOW_NAME}"
    echo CIRCLE_BUILD_URL "${CIRCLE_BUILD_URL}"
    echo CIRCLE_WORKFLOW_ID "${CIRCLE_WORKFLOW_ID}"
    echo CIRCLE_PULL_REQUEST "${CIRCLE_PULL_REQUEST}"
    echo CIRCLE_PULL_REQUEST "${CIRCLE_PULL_REQUEST}"
    echo CIRCLE_PROJECT_REPONAME "${CIRCLE_PROJECT_REPONAME}"
    echo CIRCLE_WORKFLOW_URL "${CIRCLE_WORKFLOW_URL}"
    echo PREVIOUS_BUILD_STATUS "${PREVIOUS_BUILD_STATUS}"
    echo PROJECT_SLUG "${PROJECT_SLUG}"
    echo SUCCESS_GIF "${SUCCESS_GIF}"
    echo SUCCESS_GIF "${FAIL_GIF}"
    echo PREVIOUS_BUILD_STATUS "${PREVIOUS_BUILD_STATUS}"
    echo DATA_URL "${DATA_URL}"
    echo WF_DATA "${WF_DATA}"

    RunWorkflowMonitor
}

SetupVars() {
    #https://stackoverflow.com/questions/8903239/how-to-calculate-time-elapsed-in-bash-script
    SECONDS=0
    GIT_COMMIT_DESC=$(git log --format=%B -n 1 "$CIRCLE_SHA1")
    GIT_NO_COMMITS=$(git rev-list HEAD --count)
    CIRCLE_WORKFLOW_URL="https://app.circleci.com/pipelines/workflows/${CIRCLE_WORKFLOW_ID}"
    DATA_URL="https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID/job?circle-token=${CIRCLE_TOKEN}"

    PROJECT_SLUG=${CIRCLE_BUILD_URL#https://circleci.com/}
    PROJECT_SLUG=${PROJECT_SLUG%/*}

    SetupGiphyVars
    SetupPreviousBuildVars
}

SetupGiphyVars() {
    SUCCESS_URL="http://api.giphy.com/v1/gifs/random?api_key=${GIPHY_TOKEN}&tag=${GIPHY_SUCCESS_KEYWORD}"
    SUCCESS_GIF=$(curl -s "$SUCCESS_URL" | jq -r '.data.images.downsized.url')

    FAIL_URL="http://api.giphy.com/v1/gifs/random?api_key=${GIPHY_TOKEN}&tag=${GIPHY_FAILURE_KEYWORD}"
    FAIL_GIF=$(curl -s "$FAIL_URL" | jq -r '.data.images.downsized.url')
}

SetupPreviousBuildVars() {
    local PREVIOUS_BUILD_URL="GET https://circleci.com/api/v2/insights/${PROJECT_SLUG}/workflows/${WORKFLOW_NAME}?branch=${CIRCLE_BRANCH}"

    local PREVIOUS_BUILD_URL="GET https://circleci.com/api/v2/insights/gh/martyzz1/slack-notifier/workflows/integration-test_deploy?branch=main"

    echo "Getting last known PREVIOUS_BUILD_STATUS from $PREVIOUS_BUILD_URL"
    # yamllint disable rule:line-length

    echo " PREVIOUS_BUILD_STATUS $PREVIOUS_BUILD_STATUS"
    echo "PREVIOUS_BUILD_DATA $PREVIOUS_BUILD_DATA"

    local PREVIOUS_BUILD_DATA
    PREVIOUS_BUILD_DATA=$(curl -s GET "$PREVIOUS_BUILD_URL" \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    --header "Circle-Token: ${CIRCLE_TOKEN}")

    echo "PREVIOUS_BUILD_URL $PREVIOUS_BUILD_URL"

    PREVIOUS_BUILD_STATUS=$(echo "${PREVIOUS_BUILD_DATA}" | jq -r '.items[0].status')
    # yamllint enable
    local PB_ITEMS
    PB_ITEMS=$(echo "$PREVIOUS_BUILD_DATA" | jq '.items')
    local PB_LENGTH
    PB_LENGTH=$(echo "$PB_ITEMS" | jq length)
    i="0"
    while [ "$i" -lt "$PB_LENGTH" ]
    do
      local BUILD_STATUS
      BUILD_STATUS=$(echo "${PREVIOUS_BUILD_DATA}" | jq --arg i "$i" -r ".items[$i].status")

      if [ "${BUILD_STATUS}" == "success" ] || [ "${BUILD_STATUS}" == "failed" ]; then
        PREVIOUS_BUILD_STATUS=$BUILD_STATUS
        break
      fi
      i="$((i+1))"
    done

    if [ "${PREVIOUS_BUILD_STATUS}" == "success" ] || [ "${PREVIOUS_BUILD_STATUS}" == "failed" ]; then
        echo "A known status '${PREVIOUS_BUILD_STATUS}' was detected."
    else
        # assume its the first run on this branch, so assume previously was success
        echo "An unknown status '${PREVIOUS_BUILD_STATUS}' was  detected. Setting default of 'success'"
        PREVIOUS_BUILD_STATUS='success'
    fi
}

ValidateWorkflow() {
    WF_DATA=$(curl -s "$DATA_URL")
    WF_MESSAGE=$(echo "$WF_DATA" | jq '.message')
    # Exit if no Workflow.
    if [ "$WF_MESSAGE" = "\"Workflow not found\"" ];
    then
      echo "No Workflow was found."
      echo "Your circle-token parameter may be wrong or you do not have access to this Workflow."
      exit 1
    fi
    local WF_ITEMS
    WF_ITEMS=$(echo "$WF_DATA" | jq '.items')
    local WF_LENGTH
    WF_LENGTH=$(echo "$WF_ITEMS" | jq length)
    # GET URL PATH DATA
    local VCS_SHORT
    VCS_SHORT=$(echo "$CIRCLE_BUILD_URL" | cut -d"/" -f4)
    case $VCS_SHORT in
      gh)
        VCS=github
        ;;
      bb)
        VCS=bitbucket
        ;;
      *)
        echo "No VCS found. Error" && exit 1
        ;;
    esac
    echo -e "Jobs in Workflow: $WF_LENGTH "
    # Exit if no other jobs in the Workflow.
    if [ "$WF_LENGTH" -lt "2" ];
    then
      # yamllint disable-line rule:line-length
      echo "Only a single job has been found in the workflow, indicating this reporter is the only job in the pipeline."
      echo "Please add other jobs to the Workflow that you wish report on to Slack"
      exit 0
    fi
}

RunWorkflowMonitor() {
    #####################
    ## START MAIN LOOP ##
    #####################
    # Check the status of all jobs in the workflow that are not this job
    # and wait until they have all finished.

    # Assume the WF is currently running
    local WF_FINISHED=false
    while [ "$WF_FINISHED" = false ]
    do
      local WF_DATA
      WF_DATA=$(curl -s "$DATA_URL" | jq '.items')
      echo "Waiting for other jobs to finish..."
      local WF_ITEMS
      WF_ITEMS=$(echo "$WF_DATA" | jq '.items')
      local WF_LENGTH
      WF_LENGTH=$(echo "$WF_ITEMS" | jq length)

      # for each job in the workflow fetch the status.
      # the WF_FINISHED will be assumed true unless one of the jobs in the Workflow is still running
      # the flag will then be set back to false.
      WF_FINISHED=true
      i="0"
      ################
      ### JOB LOOP ###
      ################
      while [ "$i" -lt "$WF_LENGTH" ]
      do
        echo "looping: $i"
        # fetch the job info
        local JOB_DATA
        JOB_DATA=$(echo "$WF_DATA" | jq --arg i "$i" ".[$i]")
        local JOB_NUMBER
        JOB_NUMBER=$(echo "$JOB_DATA" | jq ".job_number")
        local JOB_STATUS
        JOB_STATUS=$(echo "$JOB_DATA" | jq -r ".status")
        local JOB_NAME
        JOB_NAME=$(echo "$JOB_DATA" | jq -r ".name")
        # Only check the job if it is not this current job
        if [ "$JOB_NUMBER" = "$CIRCLE_BUILD_NUM" ];
        then
          echo "This is the reporter job. Skipping"
        else
          # If this job is NOT the current job, check the status
          echo "JOB: $JOB_NAME"
          echo "JOB NUM: $JOB_NUMBER"
          echo "STATUS: $JOB_STATUS"
          if [ "$JOB_STATUS" == "success" ];
          then
            echo "Job $JOB_NAME $JOB_NUMBER is complete - $JOB_STATUS"
          elif [ "$JOB_STATUS" == "failed" ];
          then
            echo "Job $JOB_NAME $JOB_NUMBER Failed, breaking immediately - $JOB_STATUS"
            break 2
          elif [ "$JOB_STATUS" == "on_hold" ]; #|| [ "$JOB_STATUS" == "blocked" ];
          then
            # The condition to not block metrics sending when workflow use manually approved steps or is blocked.
            echo "Job $JOB_NAME $JOB_NUMBER need manual approval - $JOB_STATUS - skipping"
          else
            # If it is still running, then mark WF_FINISHED as false.
            WF_FINISHED=false
            echo "Setting status of WF_FINISHED to false"
          fi
        fi
        echo "rerunning loop"
        i="$((i+1))"
        echo "increment loop to $i"
        echo " ---------- "
        echo
      done
      echo "Waiting 10 seconds"
      sleep 10
    done
    echo
    ################
    # WF COMPLETE  #
    ################
    echo
    echo "-------------------------------"
    echo "All jobs in Workflow complete."
    echo "-------------------------------"
    echo

}

GenerateSlackMsg() {
  duration=$SECONDS
  SLACK_MSG_DURATION="$((duration / 60)) mins and $((duration % 60)) secs"
  GenerateJobsReport
  echo "SLACK_JOBS_FIELDS=$SLACK_JOBS_FIELDS"
  GenerateMsgReport

}

GenerateJobsReport() {

    local WF_DATA
    WF_DATA=$(curl -s "$DATA_URL" | jq '.items')
    local WF_ITEMS
    WF_ITEMS=$(echo "$WF_DATA" | jq '.items')
    local WF_LENGTH
    WF_LENGTH=$(echo "$WF_ITEMS" | jq length)

    ##############Globals##############
    SLACK_JOBS_FIELDS=$(echo '[]' | jq .)
    FINAL_STATUS='success'
    # FAILED_REASON=''
    # SLACK_MSG_USER
    # SLACK_MSG_AUTHOR

    echo "Generating FINAL JOB INFORMATION"
    i=0
    while [ "$i" -lt "$WF_LENGTH" ]
      do
        echo "looping: $i"
        # fetch the job info
        local JOB_DATA
        JOB_DATA=$(echo "$WF_DATA" | jq --arg i "$i" ".[$i]")
        local JOB_NUMBER
        JOB_NUMBER=$(echo "$JOB_DATA" | jq ".job_number")
        local JOB_STATUS
        JOB_STATUS=$(echo "$JOB_DATA" | jq -r ".status")
        local JOB_NAME
        JOB_NAME=$(echo "$JOB_DATA" | jq -r ".name")
        local SLACK_JOBS_FIELDS_EMOJI=':x:'
        # Only check the job if it is not this current job
        if [ "$JOB_NUMBER" = "$CIRCLE_BUILD_NUM" ];
        then
            echo "This is the reporter job. Skipping"
        else
            # If this job is NOT the current job, check the status
            echo "JOB: $JOB_NAME"
            echo "JOB NUM: $JOB_NUMBER"
            echo "STATUS: $JOB_STATUS"

            # If $JOB_NUMBER is null, probably a blocked/queued Job.
            if [ "$JOB_NUMBER" = "null" ];
            then
                echo "skipping raw Data for JOB"
                BUILD_URL="${CIRCLE_WORKFLOW_URL}"
            else
                # yamllint disable-line rule:line-length
                local JOB_DATA_RAW
                JOB_DATA_RAW=$(curl -s "https://circleci.com/api/v1.1/project/$VCS/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME/$JOB_NUMBER?circle-token=${CIRCLE_TOKEN}")
                # removing steps and circle_yml keys from object
                JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq 'del(.circle_yml)' | jq 'del(.steps)')
                # manually set job name as it is currently null
                JOB_DATA_RAW=$(echo "$JOB_DATA_RAW" | jq --arg JOBNAME "$JOB_NAME" '.job_name = $JOBNAME')
                local BUILD_URL
                BUILD_URL=$(echo "$JOB_DATA_RAW" | jq -r ".build_url")
                SLACK_MSG_USER=$(echo "$JOB_DATA_RAW" | jq ".user")
                SLACK_MSG_AUTHOR=$(echo "$JOB_DATA_RAW" | jq -r ".author_name")
            fi
            if [ "$JOB_STATUS" == "failed" ];
            then
                echo "Job $JOB_NAME $JOB_NUMBER failed"
                FINAL_STATUS='failed'
                SLACK_JOBS_FIELDS_EMOJI=':x:'
            elif [ "$JOB_STATUS" == "success" ];
            then
                SLACK_JOBS_FIELDS_EMOJI=':white_check_mark:'
            else
                SLACK_JOBS_FIELDS_EMOJI=':no_entry_sign:'
            fi

            SLACK_JOBS_FIELDS=$(echo "$SLACK_JOBS_FIELDS" | jq --arg job "${SLACK_JOBS_FIELDS_EMOJI} *<${BUILD_URL}|$JOB_NAME>*" '. += [
                {
                    "type": "mrkdwn",
                    "text": $job
                }
            ]')

            echo "$JOB_DATA_RAW"
        fi
        echo "rerunning loop"
        i="$((i+1))"
        echo "increment loop to $i"
        echo " ---------- "
        echo
      done

}

GenerateMsgReport() {

    # Check for build state change
    if [ "$FINAL_STATUS" == "failed" ]; then
      if [ "$PREVIOUS_BUILD_STATUS" == "success" ]; then
          echo "Build was broken"
          SLACK_MSG_STATE_TITLE="${CIRCLE_USERNAME} broke the build!"
          SLACK_MSG_STATE_GIF=$FAIL_GIF
          SLACK_MSG_STATE_GIF_ALT=$GIPHY_SUCCESS_KEYWORD
      fi
      SLACK_MSG_HEADER=":x: ${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
      SLACK_MSG_COLOUR='#ed5c5c'
    else
      if [ "$PREVIOUS_BUILD_STATUS" == "failed" ]; then
          echo "Build was fixed"
          SLACK_MSG_STATE_TITLE="${CIRCLE_USERNAME} Fixed the build!"
          SLACK_MSG_STATE_GIF=$SUCCESS_GIF
          SLACK_MSG_STATE_GIF_ALT=$GIPHY_FAILURE_KEYWORD
      fi
      SLACK_MSG_HEADER=":white_check_mark: ${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
      SLACK_MSG_COLOUR='#36a64f'
    fi

    echo "Preparing initial SLACK_MSG_ATTACHMENT"
    local SLACK_MSG_ATTACHMENT
    SLACK_MSG_ATTACHMENT=$(echo "{ \"attachments\": [ { \"blocks\": [], \"color\": \"${SLACK_MSG_COLOUR}\" }] }" | jq .)

    if [ -z ${SLACK_MSG_STATE_TITLE+x} ]; then
        echo "No State Change happenned"
    else

        echo "SLACK_MSG_STATE_TITLE=$SLACK_MSG_STATE_TITLE"
        echo "SLACK_MSG_STATE_GIF=$SLACK_MSG_STATE_GIF"
        echo "SLACK_MSG_STATE_GIF_ALT=$SLACK_MSG_STATE_GIF_ALT"

        SLACK_MSG_ATTACHMENT=$(echo "$SLACK_MSG_ATTACHMENT" | jq --arg msg "$SLACK_MSG_STATE_TITLE"  --arg giphy "$SLACK_MSG_STATE_GIF" --arg alt "$SLACK_MSG_STATE_GIF_ALT" '.attachments[0].blocks += [
            {
                "type": "header",
                "text": {
                  "type": "plain_text",
                  "text": $msg,
                  "emoji": true
                }
            },
            {
                "type": "image",
                "image_url": $giphy,
                "alt_text": $alt
            }
        ]')
    fi

    echo "Preparing SLACK_MSG_HEADER"

    SLACK_MSG_ATTACHMENT=$(echo "$SLACK_MSG_ATTACHMENT" | jq --arg msg "$SLACK_MSG_HEADER" '.attachments[0].blocks += [

        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": $msg,
                "emoji": true
            }
        }
    ]')

    echo "CIRCLE_BUILD_URL=$CIRCLE_BUILD_URL"
    echo "CIRCLE_WORKFLOW_ID=$CIRCLE_WORKFLOW_ID"
    echo "CIRCLE_PULL_REQUEST=$CIRCLE_PULL_REQUEST"
    echo "CIRCLE_PROJECT_REPONAME=$CIRCLE_PROJECT_REPONAME"

    SLACK_MSG_BRANCH="*Branch:* <https://github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/tree/${CIRCLE_BRANCH}|${CIRCLE_BRANCH}>"
    SLACK_MSG_COMMIT="*Commit:* <https://github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/commit/${CIRCLE_SHA1}|${CIRCLE_SHA1:0:8}>"
    SLACK_MSG_NO_COMMITS="*Number of Commits:* $GIT_NO_COMMITS"
    SLACK_MSG_DURATION="*Duration:* $SLACK_MSG_DURATION"
    SLACK_MSG_PR="*<$CIRCLE_PULL_REQUEST|Pull Request>*"

    SLACK_MSG_ATTACHMENT=$(echo "$SLACK_MSG_ATTACHMENT" | jq --arg job "*Job:* <$CIRCLE_WORKFLOW_URL|$WORKFLOW_NAME>" --arg branch "$SLACK_MSG_BRANCH" --arg duration "$SLACK_MSG_DURATION" --arg commit "$SLACK_MSG_COMMIT" --arg pr "$SLACK_MSG_PR" --arg no_commits "$SLACK_MSG_NO_COMMITS" '.attachments[0].blocks += [
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": $job
                },
                {
                    "type": "mrkdwn",
                    "text": $branch
                },
                {
                    "type": "mrkdwn",
                    "text": $duration
                },
                {
                    "type": "mrkdwn",
                    "text": $no_commits
                },
                {
                    "type": "mrkdwn",
                    "text": $commit
                },
                {
                    "type": "mrkdwn",
                    "text": $pr
                }
            ]
        }
    ]')

    echo "Attaching SLACK_JOBS_FIELDS"
    echo "$SLACK_JOBS_FIELDS"
    SLACK_MSG_ATTACHMENT=$(echo "$SLACK_MSG_ATTACHMENT" | jq --argjson fields "$SLACK_JOBS_FIELDS" '.attachments[0].blocks += [
        {
            "type": "section",
            "fields": $fields
        }
    ]')

    SLACK_MSG_USER_AVATAR=$(echo "$SLACK_MSG_USER" | jq -r ".avatar_url")

    echo "Building SLACK_ELEMENTS_FIELDS"
    SLACK_ELEMENTS_FIELDS=$(echo '[]' | jq .)
    if [ -z ${SLACK_MSG_USER_AVATAR+x} ]; then
        echo "No Avatar detected skipping..."
    else

        echo "SLACK_ELEMENTS_FIELDS ....1"
        SLACK_ELEMENTS_FIELDS=$(echo "$SLACK_ELEMENTS_FIELDS" | jq --arg avatar "${SLACK_MSG_USER_AVATAR}" --arg author "${SLACK_MSG_AUTHOR}" '. += [
            {
                "type": "image",
                "image_url": $avatar,
                "alt_text": $author
            }
        ]')
    fi

    echo "SLACK_ELEMENTS_FIELDS ....2"
    SLACK_ELEMENTS_FIELDS=$(echo "$SLACK_ELEMENTS_FIELDS" | jq --arg commit "${GIT_COMMIT_DESC}" --arg author "Author: ${SLACK_MSG_AUTHOR}" '. += [
        {
            "type": "plain_text",
            "text": $author,
            "emoji": true
        },
        {
            "type": "plain_text",
            "text": $commit,
            "emoji": true
        }
    ]')
    echo "Attaching $SLACK_ELEMENTS_FIELDS"
    echo "$SLACK_ELEMENTS_FIELDS"

    SLACK_MSG_ATTACHMENT=$(echo "$SLACK_MSG_ATTACHMENT" | jq --argjson elements "$SLACK_ELEMENTS_FIELDS" '.attachments[0].blocks += [
        {
            "type": "context",
            "elements": $elements
        }
    ]')

    echo "$SLACK_MSG_ATTACHMENT"

}

SendSlackReport() {

    _RES=$(curl -s -X POST -H 'Content-type: application/json' --no-keepalive  --data "$SLACK_MSG_ATTACHMENT" "${SLACK_WEBHOOK}")
    echo "RESULT $_RES"
    if [ ! "$_RES" = "ok" ]; then
      exit 1
    fi
    echo "Slack status sent"

}

# Will not run if sourced for bats-core tests.
# View src/tests for more information.
ORB_TEST_ENV="bats-core"
if [ "${0#*"$ORB_TEST_ENV"}" == "$0" ]; then
    SlackMonitor
fi
