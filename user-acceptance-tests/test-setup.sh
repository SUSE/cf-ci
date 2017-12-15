#!/bin/bash
#Export CF api endpoint and create first org and space

export CF_TEST_TARGET_HOST=https://api.10.84.101.205.nip.io
cf api --skip-ssl-validation ${CF_TEST_TARGET_HOST}
cf login -u admin -p changeme
cf create-org SUSE
cf create-space -o SUSE QA
cf target -o SUSE -s QA

#behave --logging-level=ERROR
CF_TEST_TARGET_HOST=https://api.10.84.101.205.nip.io behave