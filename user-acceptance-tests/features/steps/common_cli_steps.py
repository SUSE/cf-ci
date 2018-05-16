import logging

from behave import *


@given("I have deployed the test app {appname}")
def test_app_deploy(context, appname):
    if context.CLI.app_is_deployed(appname):
        assert True
    else:
        context.CLI.push_test_app(appname)
        assert True


@when("I run 'cf {command}'")
@then("I run 'cf {command}'")
def cf_command(context, command):
    (exitcode, stdout, stderr) = context.CLI.execute_cmd(command)
    logging.debug("Client exitcode: %s", exitcode)
    logging.debug("Client stdout: %s", stdout)
    logging.debug("Client stderr: %s", stderr)
    context.exitcode = exitcode
    context.stdout = stdout
    context.stderr = stderr


@when("I push a test app '{appname}'")
def deploy_test_app(context, appname):
    context.CLI.push_test_app(appname)


@then("'{app}' should be deployed")
def app_deploy_check(context, app):
    assert context.CLI.app_is_deployed(app)


@then("'{app}' should not be deployed")
def app_deploy_failed_check(context, app):
    assert not context.CLI.app_is_deployed(app)
