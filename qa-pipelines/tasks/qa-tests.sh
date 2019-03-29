#!/bin/bash
set -o errexit

# Set kube config from pool
mkdir -p /root/.kube/
cp pool.kube-hosts/metadata /root/.kube/config

if [[ $ENABLE_QA_TESTS_PRE_UPGRADE != true ]] && [[ $ENABLE_QA_TESTS != true ]]; then
  echo "qa-tests.sh: Flag not set. Skipping QA tests"
  exit 0
fi

set -o nounset
set -o allexport
# Set this to skip a test, e.g. 002
EXCLUDE_BRAINS_PREFIX=''
CF_NAMESPACE=scf
CAP_DIRECTORY=s3.scf-config
set +o allexport

# Replace the generated monit password with the name of the generated secrets secret
DOMAIN=$(kubectl get pods -o json --namespace "${CF_NAMESPACE}" ${api_pod_name} | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
generated_secrets_secret="$(kubectl get pod ${api_pod_name} --namespace "${CF_NAMESPACE}" -o jsonpath='{@.spec.containers[0].env[?(@.name=="MONIT_PASSWORD")].valueFrom.secretKeyRef.name}')"

cd ci/qa-pipelines/qa-tests
wget "https://raw.githubusercontent.com/SUSE/scf/src/scf-release/src/acceptance-tests-brain/test-scripts/testutils.rb"
testbrain run --include 'test.rb$'
