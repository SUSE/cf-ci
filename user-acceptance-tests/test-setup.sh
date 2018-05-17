#!/bin/bash

#Export CF api endpoint and create first org and space
export CF_TEST_TARGET_HOST=${CF_TEST_TARGET_HOST:-https://api.$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')}
export CF_TEST_GLOBAL_ADMIN_USER=${CF_TEST_GLOBAL_ADMIN_USER:-admin}
export CF_TEST_GLOBAL_ADMIN_PASS=${CF_TEST_GLOBAL_ADMIN_PASS:-changeme}
export CF_TEST_GLOBAL_ADMIN_ORG=${CF_TEST_GLOBAL_ADMIN_ORG:-SUSE}
export CF_TEST_GLOBAL_ADMIN_SPACE=${CF_TEST_GLOBAL_ADMIN_SPACE:-QA}
cf api --skip-ssl-validation "${CF_TEST_TARGET_HOST}"
cf login -u "${CF_TEST_GLOBAL_ADMIN_USER}" -p "${CF_TEST_GLOBAL_ADMIN_PASS}" -o system
cf create-org "${CF_TEST_GLOBAL_ADMIN_ORG}"
cf create-space -o "${CF_TEST_GLOBAL_ADMIN_ORG}" "${CF_TEST_GLOBAL_ADMIN_SPACE}"
cf target -o "${CF_TEST_GLOBAL_ADMIN_ORG}" -s "${CF_TEST_GLOBAL_ADMIN_SPACE}"

behave
