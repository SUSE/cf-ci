#!/bin/bash
set -o errexit -o nounset

if [[ $ENABLE_CF_UPGRADE != true ]]; then
  echo "cf-upgrade.sh: Flag not set. Skipping upgrade"
  exit 0
fi

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"

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
    if [[ ${count} -gt 10800 ]]; then
      echo "Ending monitor of ${app_url} due to timeout"
      break
    fi
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
  cd ci/sample-apps/go-env
  cf push -i ${instance_count}
)

monitor_file=$(mktemp -d)/downtime.log
monitor_url "http://go-env.${DOMAIN}" "${monitor_file}" &

set_helm_params # Sets HELM_PARAMS
set_uaa_sizing_params # Adds uaa sizing params to HELM_PARAMS

helm upgrade uaa ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/ \
    --namespace "${UAA_NAMESPACE}" \
    --timeout 3600 \
    --wait \
    "${HELM_PARAMS[@]}"

# Wait for UAA release
wait_for_release uaa

# Deploy CF
CA_CERT="$(get_internal_ca_cert)"

set_helm_params # Resets HELM_PARAMS
set_scf_sizing_params # Adds scf sizing params to HELM_PARAMS

helm upgrade scf ${CAP_DIRECTORY}/helm/cf${CAP_CHART}/ \
    --namespace "${CF_NAMESPACE}" \
    --timeout 3600 \
    --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "secrets.UAA_CA_CERT=${CA_CERT}" \
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

# While the background app monitoring job is running, *and* the app isn't yet ready, sleep
while jobs %% &>/dev/null && ! tail -1 ${monitor_file} | grep -q "200 OK"; do
  sleep 1
done

# If we get here because the app is ready, monitor_url will still be running in the background
# Kill it, so we don't get any messages about the app becoming unreachable at the end
if jobs %% &>/dev/null; then
  echo "Terminating app monitoring background job"
  kill %1
fi

echo "Results of app monitoring:"
echo "SECONDS|STATUS"
uniq -c "${monitor_file}"
cf login -u admin -p changeme -o testorg -s testspace
cf delete -f go-env
cf delete-org -f testorg
