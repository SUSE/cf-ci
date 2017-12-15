from behave import *


@given("I am logged in as the {usertype} user")
@when("I am logged in as the {usertype} user")
def usertype_setup(context, usertype):
    user = 'admin'
    #user = context.users[usertype]
    password = context.default_password
    context.CLI.login(username=user, password=password)
    assert True