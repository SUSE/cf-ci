
Feature: Push Docker apps from the CLI
  In order to deploy Docker images to CAP
  As a Developer or Admin
  I want to be able to to deploy a Docker images

  Scenario: Deploy image from Docker Hub
    Given the docker image 'viovanov/node-env-tiny' from Docker Hub exists
    And I am logged in as the admin user
    And I have enabled diego_docker feature-flag
    When I push a docker app 'viovanov/node-env-tiny' as 'mydockerapp'
    Then 'mydockerapp' should be deployed
