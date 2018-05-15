"""docker-apps Test Steps"""

import requests

from behave import *


@given("the docker image '{docker_image}' from Docker Hub exists")
def docker_hub_check(context, docker_image):
    req = requests.get(
        "http://registry.hub.docker.com/v1/repositories/%s/images" %
        docker_image)
    assert req.status_code is 200


@given("Admin has enabled diego_docker feature-flag")
def enabled_diego_docker(context):
    context.CLI.execute_cmd(
        "enable-feature-flag diego_docker")

@given("I push a docker app '{docker_image}' as '{appname}'")
@when("I push a docker app '{docker_image}' as '{appname}'")
def docker_push_check(context, docker_image, appname):
    command = 'push {0} -o {1}'.format(
        appname, docker_image)
    context.return_code, context.stdout, context.stderr = \
        context.CLI.execute_cmd(command)
