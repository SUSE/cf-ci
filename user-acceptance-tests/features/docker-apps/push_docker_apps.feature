@needs-clean-org-namespace

Feature: Push Docker apps from the CLI
  As a Developer
  I want to be able to deploy Docker images

  Scenario: Deploy image from Docker Hub
    Given the docker image 'viovanov/node-env-tiny' from Docker Hub exists
    And admin has enabled diego_docker feature-flag
    And I am logged in as the developer user
    When I push a docker app 'viovanov/node-env-tiny' as 'uat-dockerapp'
    Then 'uat-dockerapp' should be deployed
