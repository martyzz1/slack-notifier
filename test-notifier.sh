#!/usr/bin/env bash

set -e

#The following can be setup in .envrc
#copy from circleci output
# export CIRCLECI=****
# export CIRCLE_BRANCH=****
# export CIRCLE_BUILD_NUM=****
# export CIRCLE_BUILD_URL=****
# export CIRCLE_COMPARE_URL=****
# export CIRCLE_JOB=****
# export CIRCLE_NODE_INDEX=****
# export CIRCLE_NODE_TOTAL=****
# export CIRCLE_PREVIOUS_BUILD_NUM=****
# export CIRCLE_PROJECT_REPONAME=****
# export CIRCLE_PROJECT_USERNAME=****
# export CIRCLE_PULL_REQUEST=****
# export CIRCLE_PULL_REQUESTS=****
# export CIRCLE_REPOSITORY_URL=****
# export CIRCLE_SHA1=****
# export CIRCLE_SHELL_ENV=****
# export CIRCLE_STAGE=****
# export CIRCLE_USERNAME=****
# export CIRCLE_WORKFLOW_ID=****
# export CIRCLE_WORKFLOW_JOB_ID=****
# export CIRCLE_WORKFLOW_UPSTREAM_JOB_IDS=****
# export CIRCLE_WORKFLOW_WORKSPACE_ID=****

#possibly included in copy, unless on master branch
# export CIRCLE_PULL_REQUEST=****
# export CIRCLE_PULL_REQUESTS=****

#Possibly we need t override to make this work in the test script
#export CIRCLE_JOB=****
#export CIRCLE_STAGE=****
#export WORKFLOW_NAME=****

#These are secrets set manually
#export CIRCLE_TOKEN=<CIRCLE_TOKEN>
#export GIPHY_TOKEN=<GIPHY_TOKEN>
#export SLACK_WEBHOOK=<SLACK_WEBHOOK_URL>

source /Users/marty/projects/martyzz1/slack-notifier/src/scripts/slack-workflow-monitor.sh
