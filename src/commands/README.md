# Commands

```yaml
description: >
  Sets up a polling job to monitor this tests workflow
  and posts a slack notification when its finished
  # What will this command do?
  # Descriptions should be short, simple, and clear.
parameters:
  circle-token:
    type: env_var_name
    default: "CIRCLE_TOKEN"
    description: >
      Enter your CircleCI Personal Access Token for interacting with the API.
      You may generate one here: https://circleci.com/account/api
  giphy-token:
    type: env_var_name
    default: "GIPHY_TOKEN"
    description: >
      Enter your giphy Personal Access Token for interacting with their API.
      You may generate one here: https://developers.giphy.com/docs/api/
  giphy-success-keyword:
    type: string
    default: "party"
  giphy-failure-keyword:
    type: string
    default: "broken"
  channel:
    type: string
    description: "Enter your slack channel"
  workflow-name:
    type: string

steps:
  - run:
      environment:
        GIPHY_SUCCESS_KEYWORD: << parameters.giphy-success-keyword>>"
        GIPHY_FAILURE_KEYWORD: << parameters.giphy-failure-keyword>>"
        WORKFLOW_NAME: << parameters.workflow-name >>"

      name: Runnning Slack Workflow Monitor
      command: <<include(scripts/slack-workflow-monitor.sh)>>

```

## See

- [Orb Author Intro](https://circleci.com/docs/2.0/orb-author-intro/#section=configuration)
- [How to author commands](https://circleci.com/docs/2.0/reusing-config/#authoring-reusable-commands)
