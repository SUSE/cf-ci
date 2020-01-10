#!/bin/bash
set -o errexit

if [[ -z "${TEST_NAME:-}" ]] ; then
    echo "run-tests.sh: No test flag set. Skipping tests"
    exit 0
fi

# Set kube config from pool
source "ci/qa-pipelines/tasks/lib/prepare-kubeconfig.sh"

set -o nounset
set -o allexport
# Set this to skip a test, e.g. 01[12] to skip tests 011 and 012
#EXCLUDE_BRAINS_REGEX=
# Set this to run only one test. If EXCLUDE and INCLUDE are both specified, EXCLUDE is applied after INCLUDE
#INCLUDE_BRAINS_REGEX=${INCLUDE_BRAINS_REGEX:-}
# Set this to define number of parallel ginkgo nodes in the acceptance test pod
#ACCEPTANCE_TEST_NODES=3
CF_NAMESPACE=kubecf
#source "ci/qa-pipelines/tasks/lib/klog-collection.sh"
#trap "upload_klogs_on_failure ${CF_NAMESPACE} ${UAA_NAMESPACE}" EXIT
#CAP_DIRECTORY=s3.scf-config
set +o allexport

# For upgrade tests
# if [[ -n "${CAP_BUNDLE_URL:-}" ]]; then
#     curl "${CAP_BUNDLE_URL}" -Lo cap-install-version.zip
#     export CAP_DIRECTORY=cap-install-version
#     unzip "${CAP_DIRECTORY}.zip" -d "${CAP_DIRECTORY}/"
# else
#     unzip "${CAP_DIRECTORY}"/*scf-*.zip -d "${CAP_DIRECTORY}/"
# fi

# Pre-set PSPs
# case "${TEST_NAME}" in
#     acceptance-tests-brain)
#         kubectl apply -f ci/qa-tools/cap-crb-tests.yaml
#         ;;
# esac

# Replace the generated monit password with the name of the generated secrets secret
#helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa/Chart.yaml  | sed 's/version: *//g' ; }
# api_pod_name=api-group-0
# DOMAIN=$(kubectl get pods -o json --namespace "${CF_NAMESPACE}" ${api_pod_name} | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
# generated_secrets_secret="$(kubectl get pod ${api_pod_name} --namespace "${CF_NAMESPACE}" -o jsonpath='{@.spec.containers[0].env[?(@.name=="MONIT_PASSWORD")].valueFrom.secretKeyRef.name}')"
# SCF_LOG_HOST=$(kubectl get pods -o json --namespace scf api-group-0 | jq -r '.spec.containers[0].env[] | select(.name == "SCF_LOG_HOST").value')
# if kubectl get storageclass | grep "persistent" > /dev/null ; then
#     STORAGECLASS="persistent"
# elif kubectl get storageclass | grep gp2 > /dev/null ; then
#     STORAGECLASS="gp2"
# fi

# kube_overrides() {
#     ruby <<EOF
#         require 'yaml'
#         require 'json'
#         exclude_brains_regex = ENV["EXCLUDE_BRAINS_REGEX"]
#         include_brains_regex = ENV["INCLUDE_BRAINS_REGEX"]

#         obj = YAML.load_file('$1')
#         values_from_secrets = ["MONIT_PASSWORD", "UAA_CLIENTS_CF_SMOKE_TESTS_CLIENT_SECRET", "AUTOSCALER_SERVICE_BROKER_PASSWORD", "INTERNAL_CA_CERT"]
#         obj['spec']['containers'].each do |container|
#             container['env'].each do |env|
#                 env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
#                 env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
#                 env['value'] = '$SCF_LOG_HOST' if env['name'] == 'SCF_LOG_HOST'
#                 env['value'] = '$STORAGECLASS' if env['name'] == 'KUBERNETES_STORAGE_CLASS_PERSISTENT'
#                 env['value'] = '$ACCEPTANCE_TEST_NODES' if env['name'] == 'ACCEPTANCE_TEST_NODES'
#                 if values_from_secrets.include? env['name']
#                     env['valueFrom']['secretKeyRef']['name'] = '$generated_secrets_secret'
#                 end
#             end
#             if obj['metadata']['name'] == "acceptance-tests-brain"
#                 unless exclude_brains_regex.empty?
#                     container['env'].push name: "EXCLUDE", value: exclude_brains_regex
#                 end
#                 unless include_brains_regex.empty?
#                     container['env'].push name: "INCLUDE", value: include_brains_regex
#                 end

#                 # CAP-370. Extend overall brain test timeout to 20
#                 # minutes. This is done to give the minibroker brain
#                 # tests enough time for all their actions even when a
#                 # slow network causes the broker to take up to 10
#                 # minutes for the assembly/delivery of the catalog.
#                 # See also "lib/cf-deploy-upgrade-common.sh" for the
#                 # corresponding CC change: BROKER_CLIENT_TIMEOUT_SECONDS.
#                 container['env'].push name: "TIMEOUT", value: "1200"
#             end
#             if obj['metadata']['name'] == "acceptance-tests"
#                 container['env'].push name: "CATS_SUITES", value: '${CATS_SUITES:-}'
#                 container['env'].push name: "CATS_RERUN", value: '${CATS_RERUN:-}'
#             end
#             container.delete "resources"
#             container['image'] = container['image'].gsub(/^.*\//, '${KUBE_REGISTRY_HOSTNAME}/${KUBE_ORGANIZATION}/')
#         end
#         puts obj.to_json
# EOF
# }

if [[ "${TEST_NAME}" == "smoke-tests" ]]; then
    container=smoke-tests-smoke-tests
elif [[ "${TEST_NAME}" == "acceptance-tests" ]]; then
    container=acceptance-tests-acceptance-tests
elif [[ "${TEST_NAME}" == "brain-tests" ]]; then
    container=acceptance-tests-brain-acceptance-tests-brain
else
    echo "Invalid TEST_NAME: ${TEST_NAME}"
    exit 1
fi

# Clean existing test jobs, if any
if [[ $(kubectl get job --namespace "${CF_NAMESPACE}" --output name | grep kubecf-"${TEST_NAME}") ]]; then
  for test_job in $(kubectl get job --namespace "${CF_NAMESPACE}" --output name | grep kubecf-"${TEST_NAME}"); do
    echo "Deleting existing test job: ${test_job}"
    kubectl delete "${test_job}" --namespace "${CF_NAMESPACE}"
fi

kubectl patch qjob --namespace "${CF_NAMESPACE}" kubecf-"${TEST_NAME}" --type merge --patch '{"spec":{"trigger":{"strategy":"now"}}}'

tests_pod_name() {
  kubectl get pods --namespace "${CF_NAMESPACE}" --output name 2> /dev/null | grep "${TEST_NAME}"
}

# Wait for tests to start.
wait_for_tests_pod() {
  local timeout="300"
  until kubectl get pods --namespace "${CF_NAMESPACE}" --output name 2> /dev/null | grep --quiet "${TEST_NAME}" || [[ "$timeout" == "0" ]]; do sleep 1; timeout=$((timeout - 1)); done
  if [[ "${timeout}" == 0 ]]; then return 1; fi
  pod_name="$(tests_pod_name)"
  until [[ "$(kubectl get "${pod_name}" --namespace "${CF_NAMESPACE}" --output jsonpath="{.status.containerStatuses[?(@.name == \"${container}\")].state.running}" 2> /dev/null)" != "" ]] || [[ "$timeout" == "0" ]]; do sleep 1; timeout=$((timeout - 1)); done
  if [[ "${timeout}" == 0 ]]; then return 1; fi
  return 0
}

echo "Waiting for the ${TEST_NAME} pod to start..."
wait_for_tests_pod || {
  >&2 echo "Timed out waiting for the ${TEST_NAME} pod"
  exit 1
}

# Follow the logs. If the tests fail, the logs command will also fail.
pod_name="$(tests_pod_name)"


kubectl logs --follow "${pod_name}" --namespace "${CF_NAMESPACE}" --container "${container}"

# Wait for the container to terminate and then exit the script with the container's exit code.
jsonpath="{.status.containerStatuses[?(@.name == \"${container}\")].state.terminated.exitCode}"
while true; do
  exit_code="$(kubectl get "${pod_name}" --namespace "${CF_NAMESPACE}" --output "jsonpath=${jsonpath}")"
  if [[ -n "${exit_code}" ]]; then
    exit "${exit_code}"
  fi
  sleep 1
done
