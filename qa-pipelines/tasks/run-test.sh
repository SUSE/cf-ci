#!/bin/bash
set -o errexit

# Set kube config from pool
mkdir -p /root/.kube/
cp pool.kube-hosts/metadata /root/.kube/config

if   [[ $ENABLE_CF_SMOKE_TESTS_PRE_UPGRADE == true ]] || \
     [[ $ENABLE_CF_SMOKE_TESTS == true ]]; then
    TEST_NAME=smoke-tests
elif [[ $ENABLE_CF_BRAIN_TESTS_PRE_UPGRADE == true ]] || \
     [[ $ENABLE_CF_BRAIN_TESTS == true ]]; then
    TEST_NAME=acceptance-tests-brain
    kubectl apply -f ci/qa-tools/cap-crb-tests.yaml
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
EXCLUDE_BRAINS_PREFIX=
# Set this to run only one test. If EXCLUDE and INCLUDE are both specified, EXCLUDE is applied after INCLUDE
INCLUDE_BRAINS_PREFIX=${INCLUDE_BRAINS_PREFIX:-}
# Set this to define number of parallel ginkgo nodes in the acceptance test pod
ACCEPTANCE_TEST_NODES=3
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
helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa/Chart.yaml  | sed 's/version: *//g' ; }
function semver_is_gte() {
  # Returns successfully if the left-hand semver is greater than or equal to the right-hand semver
  # lexical comparison doesn't work on semvers, e.g. 10.0.0 > 2.0.0
  [[ "$(echo -e "$1\n$2" |
          sort -t '.' -k 1,1 -k 2,2 -k 3,3 -g |
          tail -n 1
      )" == $1 ]]
}
if $(semver_is_gte $(helm_chart_version) 2.14.5); then
    api_pod_name=api-group-0
else
    api_pod_name=api-0
fi
DOMAIN=$(kubectl get pods -o json --namespace "${CF_NAMESPACE}" ${api_pod_name} | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
generated_secrets_secret="$(kubectl get pod ${api_pod_name} --namespace "${CF_NAMESPACE}" -o jsonpath='{@.spec.containers[0].env[?(@.name=="MONIT_PASSWORD")].valueFrom.secretKeyRef.name}')"
SCF_LOG_HOST=$(kubectl get pods -o json --namespace scf api-group-0 | jq -r '.spec.containers[0].env[] | select(.name == "SCF_LOG_HOST").value')

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        exclude_brains_prefix = ENV["EXCLUDE_BRAINS_PREFIX"]
        include_brains_prefix = ENV["INCLUDE_BRAINS_PREFIX"]

        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
                env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
                env['value'] = '$SCF_LOG_HOST' if env['name'] == 'SCF_LOG_HOST'
                env['value'] = '$ACCEPTANCE_TEST_NODES' if env['name'] == 'ACCEPTANCE_TEST_NODES'
                if env['name'] == "MONIT_PASSWORD"
                    env['valueFrom']['secretKeyRef']['name'] = '$generated_secrets_secret'
                end
                if env['name'] == "AUTOSCALER_SERVICE_BROKER_PASSWORD"
                    env['valueFrom']['secretKeyRef']['name'] = '$generated_secrets_secret'
                end
            end
            if obj['metadata']['name'] == "acceptance-tests-brain"
                unless exclude_brains_prefix.empty?
                    container['env'].push name: "EXCLUDE", value: exclude_brains_prefix
                end
                unless include_brains_prefix.empty?
                    container['env'].push name: "INCLUDE", value: include_brains_prefix
                end
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
  kubectl get --output=json --namespace="${CF_NAMESPACE}" pod $1 \
    | jq '.status.containerStatuses[0].state.terminated.exitCode | tonumber' 2>/dev/null
}

image=$(awk '$1 == "image:" { gsub(/"/, "", $2); print $2 }' "${CAP_DIRECTORY}/kube/cf/bosh-task/${TEST_NAME}.yaml")

test_pod_yml="${CAP_DIRECTORY}/kube/cf/bosh-task/${TEST_NAME}.yaml"
test_non_pods_yml=
if [[ ${TEST_NAME} == "acceptance-tests-brain" ]]; then
    test_non_pods_yml="${CAP_DIRECTORY}/kube/cf/bosh-task/${TEST_NAME}-non-pods.yaml"
    ruby <<EOF
        require 'yaml'
        yml = YAML.load_stream(File.read "${test_pod_yml}")
        non_pods_yml = yml.reject { |doc| doc["kind"] == "Pod" }
        yml.each do
            |doc|
            if doc["kind"] == "Pod"
                File.open("${test_pod_yml}", 'w') { |file| file.write(doc.to_yaml) }
            else
                File.open("${test_non_pods_yml}", 'a') { |file| file.write(doc.to_yaml) }
            end
        end
EOF
    if [[ -f "${test_non_pods_yml}" ]]; then
        kubectl create --namespace "${CF_NAMESPACE}" --filename "${test_non_pods_yml}"
    fi
fi

kubectl run \
    --namespace="${CF_NAMESPACE}" \
    --attach \
    --restart=Never \
    --image="${image}" \
    --overrides="$(kube_overrides "${test_pod_yml}")" \
    "${TEST_NAME}" ||:

while [[ -z $(container_status ${TEST_NAME}) ]]; do
    kubectl attach --namespace=scf ${TEST_NAME} ||:
done

pod_status=$(container_status ${TEST_NAME})
export CATS_RERUN=1

if [[ ${TEST_NAME} == "acceptance-tests" ]] && [[ $pod_status -gt 0 ]]; then
    # Put an actual string here, because even after failing tests, if no current failures match recurring_failures, this will
    # then get set to an empty string which is considered a passing state, since intermittent failures are nearly inevitable
    # on some platforms
    recurring_failures="unset"
    while [[ $CATS_RERUN -lt 5 ]] && [[ $pod_status -gt 0 ]] && [[ -n ${recurring_failures} ]]; do
        # Store failure messages in current_failures. The perl expression removes formatting
        current_failures=$(
            kubectl logs --namespace=scf acceptance-tests \
            | perl -pe 's@\e.*?m@@g' \
            | awk '
                /Summarizing [0-9]+ Failure/ {
                    numfailures=$2
                }
                ( numfailures > 0 ) && ( /\[Fail\]/ ) {
                    numfailures--
                    print
                }
            '
        )
        if [[ $recurring_failures == "unset" ]]; then
            recurring_failures=${current_failures}
        else
            # Get list of failures from recurring failures which reappeared in current failures
            recurring_failures=$(echo "${recurring_failures}" | grep -Fxf - <(echo "${current_failures}") || true)
            echo "Recurring failures:"
            echo "${recurring_failures}"
        fi
        if [[ -n ${recurring_failures} ]]; then
            export CATS_SUITES="=$(
                # Gets comma-separated list of all failing test suites.
                # The sed command is required because the displayed names for docker and ssh suites are different from the variable
                # expected by CATS to run those tests (diego_docker and diego_ssh respectively)
                echo "${recurring_failures}" \
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
                --overrides="$(kube_overrides "${CAP_DIRECTORY}/kube/cf/bosh-task/${TEST_NAME}.yaml")" \
                "${TEST_NAME}" ||:

            while [[ -z $(container_status ${TEST_NAME}) ]]; do
                kubectl attach --namespace=scf ${TEST_NAME} ||:
            done
            pod_status=$(container_status ${TEST_NAME})
            ((CATS_RERUN+=1))
        fi
    done
fi

if [[ ${TEST_NAME} == "acceptance-tests" ]]; then
    if [[ ${CATS_RERUN} -eq 5 ]] && [[ -n ${recurring_failures} ]]; then
        # This only happens if acceptance-tests fail 5 times with at least one error which appears in all runs
        echo "Failures which recurred in all runs"
        echo "${recurring_failures}"
    else
        # Even though the pod_status may be non-zero, set it to zero because no failures occurred in every run
        pod_status=0
   fi
fi

if [[ -f "${test_non_pods_yml}" ]]; then
    kubectl delete --namespace "${CF_NAMESPACE}" --filename "${test_non_pods_yml}"
fi
# Delete test pod if they pass. Required pre upgrade
if [[ $pod_status -eq 0 ]]; then
    kubectl delete pod --namespace=scf ${TEST_NAME}
fi
exit $pod_status
