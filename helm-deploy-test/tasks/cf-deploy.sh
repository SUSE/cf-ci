#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

set -o allexport
# The IP address assigned to the first kubelet node.
external_ip=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.unschedulable == true | not) | .metadata.annotations["alpha.kubernetes.io/provided-node-ip"]' | head -n1)
# Domain for SCF. DNS for *.DOMAIN must point to the kube node's
# external ip. This must match the value passed to the
# cert-generator.sh script.
DOMAIN=${external_ip}.nip.io
# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"
# UAA host/port that SCF will talk to.
UAA_HOST=uaa.${external_ip}.nip.io
UAA_PORT=2793

CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
set +o allexport

unzip s3.scf-config/scf-*.zip -d s3.scf-config/

# Check that the kube of the cluster is reasonable
bash s3.scf-config/kube-ready-state-check.sh kube

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
    for (( i = 0  ; i < 960 ; i ++ )) ; do
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

PROVISIONER=$(kubectl get storageclasses persistent -o "jsonpath={.provisioner}")
# Deploy UAA
kubectl create namespace "${UAA_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${UAA_NAMESPACE}/g" | kubectl create -f -
fi
helm install s3.scf-config/helm/uaa${CAP_CHART}/ \
    --namespace "${UAA_NAMESPACE}" \
    --name uaa \
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
kubectl create namespace "${CF_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${CF_NAMESPACE}/g" | kubectl create -f -
fi
helm install s3.scf-config/helm/cf${CAP_CHART}/ \
    --namespace "${CF_NAMESPACE}" \
    --name scf \
    --set "env.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "env.UAA_CA_CERT=${CA_CERT}" \
    "${HELM_PARAMS[@]}"

# Wait for CF namespace
wait_for_namespace "${CF_NAMESPACE}"
