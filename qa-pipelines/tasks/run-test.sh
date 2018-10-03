#!/bin/bash
set -o errexit

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

if   [[ $ENABLE_CF_SMOKE_TESTS_PRE_UPGRADE == true ]] || \
     [[ $ENABLE_CF_SMOKE_TESTS == true ]]; then
  TEST_NAME=smoke-tests
elif [[ $ENABLE_CF_BRAIN_TESTS_PRE_UPGRADE == true ]] || \
     [[ $ENABLE_CF_BRAIN_TESTS == true ]]; then
  TEST_NAME=acceptance-tests-brain
  if ! kubectl get clusterrolebinding -o json cap:clusterrole | jq -e  '.subjects[] | select(.name=="test-brain")' > /dev/null; then
    kubectl apply -f ci/qa-tools/cap-psp-rbac.yaml
  fi
elif [[ $ENABLE_CF_ACCEPTANCE_TESTS == true ]] || \
     [[ $ENABLE_CF_ACCEPTANCE_TESTS_PRE_UPGRADE == true ]]; then
  TEST_NAME=acceptance-tests
else
  echo "run-tests.sh: No test flag set. Skipping tests"
  exit 0
fi

set -o nounset
set -o allexport
# Set this to skip a test, e.g. 011
EXCLUDE_BRAINS_PREFIX=011
# Set this to define number of parallel ginkgo nodes in the acceptance test pod
ACCEPTANCE_TEST_NODES=3
DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
CF_NAMESPACE=scf
CAP_DIRECTORY=s3.scf-config
set +o allexport

# For upgrade tests
if [ -n "${CAP_INSTALL_VERSION:-}" ]; then
    curl ${CAP_INSTALL_VERSION} -Lo cap-install-version.zip
    export CAP_DIRECTORY=cap-install-version
    unzip ${CAP_DIRECTORY}.zip -d ${CAP_DIRECTORY}/
else
    unzip ${CAP_DIRECTORY}/scf-*.zip -d ${CAP_DIRECTORY}/
fi

# Replace the generated monit password with the name of the generated secrets secret
generated_secrets_secret="$(kubectl get pod api-0 --namespace "${CF_NAMESPACE}" -o jsonpath='{@.spec.containers[0].env[?(@.name=="MONIT_PASSWORD")].valueFrom.secretKeyRef.name}')"

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        exclude_brains_prefix = ENV["EXCLUDE_BRAINS_PREFIX"]
        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
                env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
                env['value'] = '$ACCEPTANCE_TEST_NODES' if env['name'] == 'ACCEPTANCE_TEST_NODES'
                if env['name'] == "MONIT_PASSWORD"
                    env['valueFrom']['secretKeyRef']['name'] = '$generated_secrets_secret' 
                end
            end
            if obj['metadata']['name'] == "acceptance-tests-brain" and exclude_brains_prefix
                container['env'].push name: "EXCLUDE", value: exclude_brains_prefix
            end
            if obj['metadata']['name'] == "acceptance-tests"
                container['env'].push name: "CATS_SUITES", value: '${CATS_SUITES:-}'
                container['env'].push name: "CATS_RERUN", value: '${CATS_RERUN:-}'
            end
            container.delete "resources"
        end
        puts obj.to_json
EOF
}

container_status() {
  kubectl get --output=json --namespace=scf pod $1 \
    | jq '.status.containerStatuses[0].state.terminated.exitCode | tonumber' 2>/dev/null
}

image=$(awk '$1 == "image:" { gsub(/"/, "", $2); print $2 }' "${CAP_DIRECTORY}/kube/cf${CAP_CHART}/bosh-task/${TEST_NAME}.yaml")

kubectl run \
    --namespace="${CF_NAMESPACE}" \
    --attach \
    --restart=Never \
    --image="${image}" \
    --overrides="$(kube_overrides "${CAP_DIRECTORY}/kube/cf${CAP_CHART}/bosh-task/${TEST_NAME}.yaml")" \
    "${TEST_NAME}" ||:

while [[ -z $(container_status ${TEST_NAME}) ]]; do
  kubectl attach --namespace=scf ${TEST_NAME} ||:
done

pod_status=$(container_status ${TEST_NAME})

if [[ ${TEST_NAME} == "acceptance-tests" ]] && [[ $pod_status -gt 0 ]]; then
  export CATS_RERUN=1
  while [[ $CATS_RERUN -lt 5 ]] && [[ $pod_status -gt 0 ]]; do
    export CATS_SUITES="=$(
        # Gets comma-separated list of all failing tests.
        # The first tr removes the formatting control characters from the test output, because it breaks grep
        # The sed command is required because the displayed names for docker and ssh suites are different from the variable
        # expected by CATS to run those tests (diego_docker and diego_ssh respectively)
        kubectl logs --namespace=scf ${TEST_NAME} \
        | perl -pe 's@\e.*?m@@g' \
        | grep -oE '^\[Fail\] \[[a-zA-Z_]+\]' \
        | tr -d '[]' \
        | cut -f 2 -d ' ' \
        | sort -u \
        | sed -r 's/^(docker|ssh)$/diego_\1/g' \
        | tr '\n' ','
    )"
    echo "CATS_SUITES=$CATS_SUITES"
    kubectl delete pod --namespace=scf ${TEST_NAME}
    kubectl run \
        --namespace="${CF_NAMESPACE}" \
        --attach \
        --restart=Never \
        --image="${image}" \
        --overrides="$(kube_overrides "${CAP_DIRECTORY}/kube/cf${CAP_CHART}/bosh-task/${TEST_NAME}.yaml")" \
        "${TEST_NAME}" ||:

    while [[ -z $(container_status ${TEST_NAME}) ]]; do
      kubectl attach --namespace=scf ${TEST_NAME} ||:
    done
    pod_status=$(container_status ${TEST_NAME})
    ((CATS_RERUN+=1))
  done
fi

# Delete test pod if they pass. Required pre upgrade
if [[ $pod_status -eq 0 ]]; then
  kubectl delete pod --namespace=scf ${TEST_NAME}
fi
exit $pod_status
