bats_require_minimum_version 1.5.0

# Runs prior to every test
setup() {
    # Load our script file.
    source ./src/scripts/slack-workflow-monitor.sh
    CIRCLECI_API_RETRY_DELAY=0
    CIRCLE_BUILD_URL="https://circleci.com/gh/harper-concierge/harper-api/48213"
    CIRCLE_WORKFLOW_ID="80aedf6a-483d-4095-bf10-d3f8b09b1dc6"
    DATA_URL="https://circleci.com/api/v2/workflow/$CIRCLE_WORKFLOW_ID/job"
    CALLS_FILE="$BATS_TEST_TMPDIR/curl_calls"
    echo 0 > "$CALLS_FILE"
}

# Each argument is one "<http status> <body>" response, returned by successive curl calls.
mock_curl() {
    local i=1
    for response in "$@"; do
        printf '%s' "$response" > "$BATS_TEST_TMPDIR/response.$i"
        i=$((i + 1))
    done
    curl() {
        local n
        local response
        n=$(( $(cat "$CALLS_FILE") + 1 ))
        echo "$n" > "$CALLS_FILE"
        response=$(cat "$BATS_TEST_TMPDIR/response.$n")
        printf '%s\n%s' "${response#* }" "${response%% *}"
    }
}

@test 'CircleApiGet retries a 502 and returns the next successful body' {
    mock_curl '502 <html>Bad Gateway</html>' '200 {"items":[]}'

    run --separate-stderr CircleApiGet "$DATA_URL"

    [ "$status" -eq 0 ]
    [ "$output" == '{"items":[]}' ]
    [ "$(cat "$CALLS_FILE")" -eq 2 ]
}

@test 'ValidateWorkflow fails without retrying when CircleCI rejects the token' {
    mock_curl '401 {"message":"New format tokens are needed to authenticate this API endpoint. Create a new API token for access."}'

    run ValidateWorkflow

    [ "$status" -eq 1 ]
    [ "$(cat "$CALLS_FILE")" -eq 1 ]
}

@test 'RunWorkflowMonitor keeps polling after a failed poll until the jobs finish' {
    sleep() { :; }
    CIRCLECI_API_ATTEMPTS=1
    CIRCLE_BUILD_NUM=1
    mock_curl '503 Service Unavailable' \
        '200 {"items":[{"job_number":1,"name":"slack-monitor","status":"running"},{"job_number":2,"name":"build","status":"success"}]}'

    run RunWorkflowMonitor

    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS_FILE")" -eq 2 ]
    [[ "$output" == *"All jobs in Workflow complete."* ]]
}
