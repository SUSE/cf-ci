#!/bin/bash
set -o errexit -o nounset

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"
source "ci/qa-pipelines/tasks/lib/klog-collection.sh"
trap "upload_klogs_on_failure ${CF_NAMESPACE} ${UAA_NAMESPACE}" EXIT

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

pxc_post_upgrade() {
  [[ "${HA}" == true ]]
}

# For now we will keep on using custom sizing for UAA.
# Until CATs failures issue is addressed.
export CUSTOM_UAA_SIZING=true

# We can remove the custom scf sizing after 1.5 release.
if pxc_post_upgrade; then
   export CUSTOM_SCF_SIZING=true
fi

set_helm_params # Sets HELM_PARAMS.
set_uaa_params # Adds uaa specific params to HELM_PARAMS.

# Explicitly setting mysql count to 1 for pxc upgrade testing for uaa.
if pxc_post_upgrade; then
  HELM_PARAMS+=(--set=sizing.mysql.count=1)
fi

echo "UAA customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

if [[ "${EMBEDDED_UAA:-false}" != "true" ]]; then
  helm upgrade uaa ${CAP_DIRECTORY}/helm/uaa/ \
      --namespace "${UAA_NAMESPACE}" \
      --recreate-pods \
      --timeout 3600 \
      --wait \
      "${HELM_PARAMS[@]}"

  # Wait for UAA release
  wait_for_release uaa
fi

# Deploy CF
set_helm_params # Resets HELM_PARAMS.
set_scf_params # Adds scf specific params to HELM_PARAMS.

# Explicitly setting mysql count to 1 for pxc upgrade testing for scf.
if pxc_post_upgrade; then
  HELM_PARAMS+=(--set=sizing.mysql.count=1)
fi

echo "SCF customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

helm upgrade scf ${CAP_DIRECTORY}/helm/cf/ \
    --namespace "${CF_NAMESPACE}" \
    --recreate-pods \
    --timeout 3600 \
    --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "env.SCF_LOG_HOST=${SCF_LOG_HOST}" \
    --set "env.INSECURE_DOCKER_REGISTRIES=${INSECURE_DOCKER_REGISTRIES}" \
    --wait \
    "${HELM_PARAMS[@]}"

# Wait for CF release
wait_for_release scf

if pxc_post_upgrade; then
  echo "Deleting left-over PVCs for UAA..."
  kubectl delete pvc -n uaa mysql-data-mysql-1
  
  echo "Deleting left-over PVCs for SCF..."
  kubectl delete pvc -n scf mysql-data-mysql-1

  # Restoring the HA configuration after mysql to pxc migration.
  echo "Applying actual UAA HA config..."
  set_helm_params # Resets HELM_PARAMS.
  set_uaa_params # Adds uaa specific params to HELM_PARAMS.
  
  echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'
  
  helm upgrade uaa ${CAP_DIRECTORY}/helm/uaa/ \
      --namespace "${UAA_NAMESPACE}" \
      --timeout 600 \
      "${HELM_PARAMS[@]}"

  # Wait for UAA release
  wait_for_release uaa

  # Now we can turn off custom sizing for scf to start using config.HA=true.
  export CUSTOM_SCF_SIZING=false
  
  echo "Applying actual SCF HA config..."
  set_helm_params # Resets HELM_PARAMS.
  set_scf_params # Adds scf specific params to HELM_PARAMS.
  echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'
  helm upgrade scf ${CAP_DIRECTORY}/helm/cf/ \
      --namespace "${CF_NAMESPACE}" \
      --timeout 3600 \
      --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
      --set "env.UAA_HOST=${UAA_HOST}" \
      --set "env.UAA_PORT=${UAA_PORT}" \
      --set "env.SCF_LOG_HOST=${SCF_LOG_HOST}" \
      --set "env.INSECURE_DOCKER_REGISTRIES=${INSECURE_DOCKER_REGISTRIES}" \
      --wait \
      "${HELM_PARAMS[@]}"

  # Wait for CF release
  wait_for_release scf
fi

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

trap "" EXIT
