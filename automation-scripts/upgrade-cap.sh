#!/bin/bash

# Install and upgrade CAP using HELM repo
set -o errexit -o nounset
#set -x

# Set variables
external_ip=${EXTERNAL_IP:-}
KUBE_REGISTRY_HOSTNAME=${DOCKER_INTERNAL_REGISTRY}
KUBE_REGISTRY_USERNAME=${DOCKER_INTERNAL_USERNAME}
KUBE_REGISTRY_PASSWORD=${DOCKER_INTERNAL_PASSWORD}
KUBE_ORGANIZATION=splatform
CAP_CHART=""  # use -opensuse for CAP-opensuse installs
cap_install_version=${CAP_INSTALL_VERSION:-}
cap_install_url=${CAP_INSTALL_URL:-}
cap_upgrade_version=${CAP_UPGRADE_VERSION:-}
cap_upgrade_url=${CAP_UPGRADE_URL:-}

# Domain for SCF. DNS for *.DOMAIN must point to the kube node's
# external ip.
DOMAIN=${external_ip}.nip.io
# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"
# UAA host/port that SCF will talk to.
UAA_HOST=uaa.${external_ip}.nip.io
UAA_PORT=2793

CF_NAMESPACE=scf
UAA_NAMESPACE=uaa

# Fetch CAP bundle
curl ${cap_install_url} -o ${cap_install_version}.zip
curl ${cap_upgrade_url} -o ${cap_upgrade_version}.zip

HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
             --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
             --set "kube.external_ip=${external_ip}"
             --set "kube.auth=rbac")
if [ -n "${KUBE_REGISTRY_HOSTNAME:-}" ]; then
    HELM_PARAMS+=(--set "kube.registry.hostname=${KUBE_REGISTRY_HOSTNAME}")
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
is_namespace_pending() {
    local namespace="$1"
    if kubectl get pods --namespace="${namespace}" --output=custom-columns=':.status.conditions[?(@.type == "Ready")].status' | grep --silent False ; then
        return 0
    fi
    return 1
}

wait_for_namespace() {
    local namespace="$1"
    start=$(date +%s)
    for (( i = 0  ; i < 480 ; i ++ )) ; do
        if ! is_namespace_pending "${namespace}" ; then
            break
        fi
        now=$(date +%s)
        printf "\rWaiting for %s at %s (%ss)..." "${namespace}" "$(date --rfc-2822)" $((${now} - ${start}))
        sleep 10
    done
    now=$(date +%s)
    printf "\rDone waiting for %s at %s (%ss)\n" "${namespace}" "$(date --rfc-2822)" $((${now} - ${start}))
    kubectl get pods --namespace="${namespace}"
    if is_namespace_pending "${namespace}" ; then
        printf "Namespace %s is still pending\n" "${namespace}"
        exit 1
    fi 
}

# unzip CAP bundle
unzip ${cap_install_version}.zip -d ${cap_install_version}

# Deploy UAA
helm install ${cap_install_version}/helm/uaa${CAP_CHART}/ \
    -n uaa \
    --namespace "${UAA_NAMESPACE}" \
    "${HELM_PARAMS[@]}"

# Wait for UAA namespace
wait_for_namespace "${UAA_NAMESPACE}"

get_uaa_secret () {
    kubectl get secret secret \
    --namespace uaa \
    -o jsonpath="{.data['$1']}"
}

CA_CERT="$(get_uaa_secret internal-ca-cert | base64 -d -)"

# Deploy CF
helm install ${cap_install_version}/helm/cf${CAP_CHART}/ \
    -n scf \
    --namespace "${CF_NAMESPACE}" \
    --set "env.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "env.HCP_CA_CERT=${CA_CERT}" \
    "${HELM_PARAMS[@]}"

# Wait for CF namespace
wait_for_namespace "${CF_NAMESPACE}"   

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
                env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
            end
        end
        puts obj.to_json
EOF
}

run_tests() {
    local test_name="$1"
    local cap_bundle="$2"
    image=$(awk '$1 == "image:" { gsub(/"/, "", $2); print $2 }' "${cap_bundle}/kube/cf${CAP_CHART}/bosh-task/${test_name}.yaml")
    kubectl run \
        --namespace="${CF_NAMESPACE}" \
        --attach \
        --restart=Never \
        --image="${image}" \
        --overrides="$(kube_overrides "${cap_bundle}/kube/cf${CAP_CHART}/bosh-task/${test_name}.yaml")" \
        "${test_name}"
}

# Run smoke-tests
run_tests smoke-tests ${cap_install_version}

# Run acceptance-tests-brain
run_tests acceptance-tests-brain ${cap_install_version}

# DO NOT RUN CATS

# Clean CAP bundles
rm -rf ${cap_install_version}/
rm ${cap_install_version}.zip

# unzip CAP bundle
unzip ${cap_upgrade_version}.zip -d ${cap_upgrade_version}

# Upgrade UAA
helm upgrade uaa ${cap_upgrade_version}/helm/uaa${CAP_CHART}/ \
    --namespace "${UAA_NAMESPACE}" \
    "${HELM_PARAMS[@]}"

# Wait for UAA namespace
wait_for_namespace "${UAA_NAMESPACE}"

get_uaa_secret () {
    kubectl get secret secret \
    --namespace uaa \
    -o jsonpath="{.data['$1']}"
}

CA_CERT="$(get_uaa_secret internal-ca-cert | base64 -d -)"

# Upgrade CF
helm upgrade scf ${cap_upgrade_version}/helm/cf${CAP_CHART}/ \
    --namespace "${CF_NAMESPACE}" \
    --set "env.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "env.UAA_CA_CERT=${CA_CERT}" \
    "${HELM_PARAMS[@]}"

# Wait for CF namespace
wait_for_namespace "${CF_NAMESPACE}"

# Delete old test pods
kubectl delete pod -n scf smoke-tests
kubectl delete pod -n scf acceptance-tests-brain

# Run smoke-tests
run_tests smoke-tests ${cap_upgrade_version}

# Run acceptance-tests-brain
run_tests acceptance-tests-brain ${cap_upgrade_version}

# Run CATS
run_tests acceptance-tests ${cap_upgrade_version}

# Teardown
for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
    for name in $(helm list --deployed --short --namespace "${namespace}") ; do
        helm delete "${name}" || true
    done
    while kubectl get namespace "${namespace}" ; do
        kubectl delete namespace "${namespace}" || true
        sleep 10
    done
done

# Clean CAP bundles
rm -rf ${cap_upgrade_version}/
rm ${cap_upgrade_version}.zip
