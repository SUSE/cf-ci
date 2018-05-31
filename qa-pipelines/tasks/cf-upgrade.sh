#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

set -o allexport
# The IP address assigned to the first kubelet node.
#external_ip=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.unschedulable == true | not) | .metadata.annotations["alpha.kubernetes.io/provided-node-ip"]' | head -n1)
private_ip=10.240.0.4
external_ip=104.42.44.151
# Domain for SCF. DNS for *.DOMAIN must point to the kube node's
# external ip. This must match the value passed to the
# cert-generator.sh script.
DOMAIN=${external_ip}.${MAGIC_DNS_SERVICE}
# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"
# UAA host/port that SCF will talk to.
UAA_HOST=uaa.${external_ip}.${MAGIC_DNS_SERVICE}
UAA_PORT=2793

CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
CAP_DIRECTORY=s3.scf-config
set +o allexport

# Delete old test pods
kubectl delete pod -n scf smoke-tests
#kubectl delete pod -n scf acceptance-tests-brain

unzip ${CAP_DIRECTORY}/scf-*.zip -d ${CAP_DIRECTORY}/

# Check that the kube of the cluster is reasonable
bash ${CAP_DIRECTORY}/kube-ready-state-check.sh kube

HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
             --set "secrets.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
             --set "kube.external_ips[0]=${private_ip}"
             --set "kube.auth="
             --set "kube.storage_class.persistent=default")
if [ -n "${KUBE_REGISTRY_HOSTNAME:-}" ]; then
    HELM_PARAMS+=(--set "kube.registry.hostname=${KUBE_REGISTRY_HOSTNAME%/}")
fi
if [ -n "${KUBE_REGISTRY_USERNAME:-}" ]; then
    HELM_PARAMS+=(--set "kube.registry.username=${KUBE_REGISTRY_USERNAME}")
fi
if [ -n "${KUBE_REGISTRY_PASSWORD:-}" ]; then
    HELM_PARAMS+=(--set "kube.registry.password=${KUBE_REGISTRY_PASSWORD}")
fi
if [ -n "${KUBE_ORGANIZATION:-}" ]; then
   HELM_PARAMS+=(--set "kube.organization=${KUBE_ORGANIZATION}")
fi

# Wait until CF namespaces are ready
is_namespace_ready() {
    local namespace="$1"

    # Create regular expression to match active_passive_pods
    # These are scaled services which are expected to only have one pod listed as ready
    local active_passive_pod_regex='^diego-api$|^diego-brain$|^routing-api$'
    local active_passive_role_count=$(awk -F '|' '{ print NF }' <<< "${active_passive_pod_regex}")

    # Get the container name and status for each pod in two columns
    # The name here will be the role name, not the pod name, e.g. 'diego-brain' not 'diego-brain-1'
    local active_passive_pod_status=$(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].name,:.status.containerStatuses[].ready' \
        | awk '$1 ~ '"/${active_passive_pod_regex}/")

    # Check that the number of containers which are ready is equal to the number of active passive roles 
    if [[ -n $active_passive_pod_status ]] && [[ $(echo "$active_passive_pod_status" | grep true | wc -l) -ne ${active_passive_role_count} ]]; then
        return 1
    fi

    # Finally, check that all pods which do not match the active_passive_pod_regex are ready
    [[ true == $(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].name,:.status.containerStatuses[].ready' \
        | awk '$1 !~ '"/${active_passive_pod_regex}/ { print \$2 }" \
        | sed '/^ *$/d' \
        | sort \
        | uniq) ]]
}

wait_for_namespace() {
    local namespace="$1"
    start=$(date +%s)
    for (( i = 0  ; i < 960 ; i ++ )) ; do
        if is_namespace_ready "${namespace}" ; then
            break
        fi
        now=$(date +%s)
        printf "\rWaiting for %s at %s (%ss)..." "${namespace}" "$(date --rfc-2822)" $((${now} - ${start}))
        sleep 10
    done
    now=$(date +%s)
    printf "\rDone waiting for %s at %s (%ss)\n" "${namespace}" "$(date --rfc-2822)" $((${now} - ${start}))
    kubectl get pods --namespace="${namespace}"
    if ! is_namespace_ready "${namespace}" ; then
        printf "Namespace %s is still pending\n" "${namespace}"
        exit 1
    fi 
}

# PROVISIONER=$(kubectl get storageclasses persistent -o "jsonpath={.provisioner}")

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

# push app in subshell to avoid changing directory
(
  cd ci/sample-apps/go-env
  cf api --skip-ssl-validation "https://api.${DOMAIN}"
  cf login -u admin -p changeme
  cf create-org testorg
  cf target -o testorg
  cf create-space testspace
  cf target -o testorg -s testspace
  instance_count=$(helm get scf  | ruby -rjson -ryaml -e 'puts YAML.load(ARGF.read)["sizing"]["diego_cell"]["count"]')
  cf push -i ${instance_count}
)

monitor_file=$(mktemp -d)/downtime.log
monitor_url "http://go-env.${DOMAIN}" "${monitor_file}" &

# Upgrade UAA
helm upgrade uaa ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/ \
    --namespace "${UAA_NAMESPACE}" \
    --timeout 600 \
    "${HELM_PARAMS[@]}"

# Wait for UAA namespace
wait_for_namespace "${UAA_NAMESPACE}"

# Get the version of the helm chart for uaa
helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/Chart.yaml  | sed 's/version: *//g' ; }
generated_secrets_secret() { kubectl get --namespace "${UAA_NAMESPACE}" secrets --output "custom-columns=:.metadata.name" | grep -F "secrets-$(helm_chart_version)-" | sort | tail -n 1 ; }
get_internal_ca_cert() {
    local uaa_secret_name=$(generated_secrets_secret)
    kubectl get secret ${uaa_secret_name} \
      --namespace "${UAA_NAMESPACE}" \
      -o jsonpath="{.data['internal-ca-cert']}" \
      | base64 -d
}

CA_CERT="$(get_internal_ca_cert)"

# Upgrade CF
if [[ ${HA} == true ]]; then
  HELM_PARAMS+=(--set=sizing.HA=true)
fi

if [[ ${SCALED_HA} == true ]]; then
  HELM_PARAMS+=(--set=sizing.routing_api.count=1)
  HELM_PARAMS+=(--set=sizing.{api,cc_uploader,cc_worker,cf_usb,diego_access,diego_brain,doppler,loggregator,mysql,nats,router,syslog_adapter,syslog_rlp,tcp_router,mysql_proxy}.count=2)
  HELM_PARAMS+=(--set=sizing.{diego_api,diego-locket,diego_cell}.count=3)
fi

helm upgrade scf ${CAP_DIRECTORY}/helm/cf${CAP_CHART}/ \
    --namespace "${CF_NAMESPACE}" \
    --timeout 600 \
    --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "secrets.UAA_CA_CERT=${CA_CERT}" \
    "${HELM_PARAMS[@]}"

# Wait for CF namespace
wait_for_namespace "${CF_NAMESPACE}"
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
