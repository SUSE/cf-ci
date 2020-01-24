#!/bin/bash
set -o errexit -o nounset

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"
source "ci/qa-pipelines/tasks/lib/klog-collection.sh"
trap "upload_klogs_on_failure ${CF_NAMESPACE} ${UAA_NAMESPACE}" EXIT
monitor_kubectl_pods &


# monitor_url takes a URL argument and a path to a log file
# This will time out after 3 hours. Until then, repeatedly curl the URL with a 1-second wait period, and log the response
# If the application state changes, print this to stdout as well
monitor_url() {
  local app_url=$1
  local log_file=$2
  local count=0
  local last_state=
  local new_state=
  echo "monitoring URL ${app_url}"
  while true; do
    new_state=$({ curl -sI "${1}" || echo "URL could not be reached"; } | head -n1 | tee -a "${log_file}")
    if [[ "${new_state}" != "${last_state}" ]]; then
      echo "state change for ${1}: ${new_state}"
      last_state=$new_state
    fi
    ((++count))
    sleep 1
  done
}

# Create pre-upgrade user, testorg and Push pre-upgrade app
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o system
cf create-user pre-upgrade-user pre-upgrade-user
cf create-org testorg
cf target -o testorg
cf create-space testspace
cf target -o testorg -s testspace
instance_count=$(kubectl get statefulsets -o json diego-cell --namespace scf | jq .spec.replicas)
# push app in subshell to avoid changing directory
(
  cd ci/sample-apps/test-app
  cf push -i ${instance_count} test-app
)

monitor_file=$(mktemp -d)/downtime.log
monitor_url "http://test-app.${DOMAIN}" "${monitor_file}" &

if [[ "${EXTERNAL_DB:-false}" == "true" ]]; then
    export EXTERNAL_DB_PASS="$(kubectl get secret -n external-db external-db-mariadb -o jsonpath='{.data.mariadb-root-password}' | base64 --decode)"
fi

set_helm_params # Sets HELM_PARAMS.
set_uaa_params # Adds uaa specific params to HELM_PARAMS.

echo "UAA customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

if [[ "${EMBEDDED_UAA:-false}" != "true" ]]; then
  helm upgrade uaa ${CAP_DIRECTORY}/helm/uaa/ \
      --namespace "${UAA_NAMESPACE}" \
      --recreate-pods \
      --timeout 7200 \
      --wait \
      "${HELM_PARAMS[@]}"

  # Wait for UAA release
  wait_for_release uaa
fi

# Deploy CF
set_helm_params # Resets HELM_PARAMS.
set_scf_params # Adds scf specific params to HELM_PARAMS.

# When this upgrade task is running in an HA job, and we want to test config.HA_strict:
if [[ "${HA}" == true ]] && [[ -n "${HA_STRICT:-}" ]]; then
    HELM_PARAMS+=(--set "config.HA_strict=${HA_STRICT}")
    HELM_PARAMS+=(--set "sizing.diego_api.count=1")
fi

echo "SCF customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

helm upgrade scf ${CAP_DIRECTORY}/helm/cf/ \
    --namespace "${CF_NAMESPACE}" \
    --recreate-pods \
    --timeout 7200 \
    --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "env.SCF_LOG_HOST=${SCF_LOG_HOST}" \
    --set "env.INSECURE_DOCKER_REGISTRIES=${INSECURE_DOCKER_REGISTRIES}" \
    --wait \
    "${HELM_PARAMS[@]}"

# Wait for CF release
wait_for_release scf

echo "Post Upgrade Users and Orgs State:"
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o system
echo "List of Orgs, post-upgrade:"
cf orgs
echo "Checking /v2/users for 'pre-upgrade-user':"
cf curl /v2/users | jq -e '.resources[] | .entity.username | select( . == "pre-upgrade-user")'

# Sleep until the monitored app is ready again, post-upgrade
while ! tail -1 ${monitor_file} | grep -q "200 OK"; do
  sleep 1
done

# Kill the app monitoring job (always the most recently backgrounded job),
# so we don't get any messages about the app becoming unreachable at the end
echo "Terminating app monitoring background job"
kill %%

echo "Results of app monitoring:"
echo "SECONDS|STATUS"
uniq -c "${monitor_file}"
cf login -u admin -p changeme -o testorg -s testspace
cf delete -f test-app
cf delete-org -f testorg

trap "" EXIT
