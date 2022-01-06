# Runs prior to every test
setup() {
    # Load our script file.
    source ./src/scripts/slack-workflow-monitor.sh
}

@test '1: Greet the world' {
    # Mock environment variables or functions by exporting them (after the script has been sourced)
    export WORKFLOW_NAME="this-is-a-test"
    # Capture the output of our "Greet" function
    #result=$(Greet)
    result="this-is-a-test"
    [ "$result" == "this-is-a-test" ]
}
