"""Test Environment Setup"""

import os
import random
import re
import string

from support.cf_cli import CLI

TARGET_HOST = os.environ["CF_TEST_TARGET_HOST"]

# these are the defaults that are setup prior to the tests being run
# we don't use them in the actual tests
GLOBAL_ADMIN_USER = os.getenv("CF_TEST_GLOBAL_ADMIN_USER", "admin")
GLOBAL_ADMIN_PASS = os.getenv("CF_TEST_GLOBAL_ADMIN_PASS", "changeme")
GLOBAL_DEFAULT_ORG = os.getenv("CF_TEST_GLOBAL_ADMIN_ORG", "SUSE")
GLOBAL_DEFAULT_SPACE = os.getenv("CF_TEST_GLOBAL_ADMIN_SPACE", "QA")
GLOBAL_DEFAULT_PASS = os.getenv(
    "CF_TEST_GLOBAL_DEFAULT_PASS", "changeme")


def generate_random_namespace(context, name):
    """Sets up random namespace based on feature name"""
    # creates a random prefix based on the feature name
    my_namespace = re.sub(' ', '', name).lower()[:8]
    randstring = ''.join(
        random.choice(
            string.ascii_uppercase +
            string.digits) for _ in range(6))
    context.namespace = my_namespace + "-" + randstring

    # creates an org and space based on this prefix and sets them to the
    # CLI defaults
    context.CLI.setup_namespace(context.namespace)

def create_developer_user(context):
    """Create an developer user in the context's namespace"""
    # creates an developer user with the prefix and stores it in the context
    context.users['developer'] = context.namespace
    context.CLI.execute_cmd(
        "create-user %s %s " %
        ("developer@" + context.namespace, GLOBAL_DEFAULT_PASS))
    context.CLI.execute_cmd(
        "set-org-role %s %s OrgManager" %
        ("developer@" + context.namespace, context.namespace + "-org"))
    context.CLI.execute_cmd(
        "set-space-role %s %s %s SpaceDeveloper" %
        ("developer@" + context.namespace, context.namespace + "-org", context.namespace + "-space"))

    #TODO: quotas implementation
    # context.CLI.execute_cmd("create-quota %s-quota" % context.namespace)
    # context.CLI.execute_cmd(
    #     "quota-org %s-org %s-quota" %
    #     (context.namespace, context.namespace))

def before_feature(context, feature):
    """Per-feature behave environment setup"""
    context.target = TARGET_HOST
    context.users = {}
    context.default_password = GLOBAL_DEFAULT_PASS

    context.CLI = CLI()
    context.CLI.target(context.target)

    # login as the global admin user admin/changmeme to setup our test
    # environment
    context.CLI.login(username=GLOBAL_ADMIN_USER,
                      password=GLOBAL_ADMIN_PASS,
                      org=GLOBAL_DEFAULT_ORG,
                      space=GLOBAL_DEFAULT_SPACE)

    if "needs-clean-org-namespace" in context.tags:
        generate_random_namespace(context, feature.name)
        create_developer_user(context)

#TODO: def after_feature(context, feature)
