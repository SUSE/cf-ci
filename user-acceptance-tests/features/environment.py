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
