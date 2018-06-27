#!/bin/bash
# Deploys CAP 1.1.1 on caasp2 on engcloud and run smoke tests
# usage: PRIVATE_IP=172.28.0.11 EXTERNAL_IP=10.86.0.156 DOCKER_INTERNAL_REGISTRY= DOCKER_INTERNAL_USERNAME= DOCKER_INTERNAL_PASSWORD= bash cap-deploy-on-engcloud.sh
set -o errexit -o nounset
set -x

# Set variables
MAGIC_DNS_SERVICE=omg.howdoi.website
private_ip=${PRIVATE_IP}
external_ip=${EXTERNAL_IP}
DOMAIN=${external_ip}.${MAGIC_DNS_SERVICE}
UAA_HOST=uaa.${external_ip}.${MAGIC_DNS_SERVICE}
KUBE_REGISTRY_HOSTNAME=${DOCKER_INTERNAL_REGISTRY}
KUBE_REGISTRY_USERNAME=${DOCKER_INTERNAL_USERNAME}
KUBE_REGISTRY_PASSWORD=${DOCKER_INTERNAL_PASSWORD}
HA=false
SCALED_HA=true
CAP_INSTALL_VERSION=https://s3.amazonaws.com/cap-release-archives/master/scf-sle-2.10.1%2Bcf1.15.0.0.g647b2273.zip

CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
CAP_CHART=""
#CAP_CHART="-opensuse"

KUBE_ORGANIZATION=splatform
# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"
# UAA host/port that SCF will talk to.
UAA_PORT=2793
CAP_DIRECTORY=s3.scf-config

# For upgrades tests
if [ -n "${CAP_INSTALL_VERSION:-}" ]; then
    curl ${CAP_INSTALL_VERSION} -Lo cap-install-version.zip
    export CAP_DIRECTORY=cap-install-version
    unzip ${CAP_DIRECTORY}.zip -d ${CAP_DIRECTORY}/
else
    unzip ${CAP_DIRECTORY}/scf-*.zip -d ${CAP_DIRECTORY}/
fi

# Get the version of the helm chart for uaa
helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/Chart.yaml  | sed 's/version: *//g' ; }

function semver_is_gte() {
  # Returns successfully if the left-hand semver is greater than or equal to the right-hand semver
  # lexical comparison doesn't work on semvers, e.g. 10.0.0 > 2.0.0
  [[ "$(echo -e "$1\n$2" |
        sort -t '.' -k 1,1 -k 2,2 -k 3,3 -g |
        tail -n 1
    )" == $1 ]]
}

if semver_is_gte $(helm_chart_version) 2.7.3; then
  USER_PROVIDED_VALUES_KEY=secrets
else
  USER_PROVIDED_VALUES_KEY=env
fi

# Check that the kube of the cluster is reasonable
bash ${CAP_DIRECTORY}/kube-ready-state-check.sh kube

if semver_is_gte $(helm_chart_version) 2.8.0; then
    HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
                 --set "${USER_PROVIDED_VALUES_KEY}.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
                 --set "kube.external_ips[0]=${private_ip}")
else
    HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
                 --set "${USER_PROVIDED_VALUES_KEY}.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
                 --set "kube.external_ip=${private_ip}"
                 --set "kube.auth=rbac")
fi
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

PROVISIONER=$(kubectl get storageclasses persistent -o "jsonpath={.provisioner}")
# Deploy UAA
kubectl create namespace "${UAA_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${UAA_NAMESPACE}/g" | kubectl create -f -
fi
helm install ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/ \
    --namespace "${UAA_NAMESPACE}" \
    --name uaa \
    --timeout 600 \
    "${HELM_PARAMS[@]}"

# Wait for UAA namespace
wait_for_namespace "${UAA_NAMESPACE}"


generated_secrets_secret() { kubectl get --namespace "${UAA_NAMESPACE}" secrets --output "custom-columns=:.metadata.name" | grep -F "secrets-$(helm_chart_version)-" | sort | tail -n 1 ; }
get_internal_ca_cert() {
    local uaa_secret_name
    if semver_is_gte $(helm_chart_version) 2.7.3; then
        uaa_secret_name=$(generated_secrets_secret)
    else
        uaa_secret_name=secret
    fi
    kubectl get secret ${uaa_secret_name} \
      --namespace "${UAA_NAMESPACE}" \
      -o jsonpath="{.data['internal-ca-cert']}" \
      | base64 -d 
}

CA_CERT="$(get_internal_ca_cert)"

# Deploy CF
kubectl create namespace "${CF_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${CF_NAMESPACE}/g" | kubectl create -f -
fi

if [[ ${HA} == true ]]; then
  HELM_PARAMS+=(--set=sizing.HA=true)
fi

if [[ ${SCALED_HA} == true ]]; then
  HELM_PARAMS+=(--set=sizing.routing_api.count=1)
  HELM_PARAMS+=(--set=sizing.{api,cc_uploader,cc_worker,cf_usb,diego_access,diego_brain,doppler,loggregator,mysql,nats,router,syslog_adapter,syslog_rlp,tcp_router,mysql_proxy}.count=2)
  HELM_PARAMS+=(--set=sizing.{diego_api,diego-locket,diego_cell}.count=3)
fi

helm install ${CAP_DIRECTORY}/helm/cf${CAP_CHART}/ \
    --namespace "${CF_NAMESPACE}" \
    --name scf \
    --timeout 600 \
    --set "${USER_PROVIDED_VALUES_KEY}.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "${USER_PROVIDED_VALUES_KEY}.UAA_CA_CERT=${CA_CERT}" \
    "${HELM_PARAMS[@]}"

# Wait for CF namespace
wait_for_namespace "${CF_NAMESPACE}"


# Run Smoke tests
TEST_NAME=smoke-tests

# Replace the generated monit password with the name of the generated secrets secret
generated_secrets_secret="$(kubectl get pod api-0 --namespace "${CF_NAMESPACE}" -o jsonpath='{@.spec.containers[0].env[?(@.name=="MONIT_PASSWORD")].valueFrom.secretKeyRef.name}')"

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
                env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
                if env['name'] == "MONIT_PASSWORD"
                    env['valueFrom']['secretKeyRef']['name'] = '$generated_secrets_secret' 
                end
            end
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

exit $(container_status ${TEST_NAME})
