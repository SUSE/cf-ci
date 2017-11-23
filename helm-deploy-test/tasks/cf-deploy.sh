#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

set -o allexport
# The IP address assigned to the kube node.
external_ip=$(kubectl get nodes -o jsonpath='{.items[].status.addresses[?(@.type=="InternalIP")].address}' | head -n1)
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

# Generate certificates
mkdir certs/
pushd s3.scf-config/
./cert-generator.sh -d "${DOMAIN}" -n "${CF_NAMESPACE}" -o ../certs/
popd

HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
             --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
             --set "kube.external_ip=${external_ip}")
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

# Deploy UAA
kubectl create namespace "${UAA_NAMESPACE}"
helm install s3.scf-config/helm/uaa/ \
    --namespace "${UAA_NAMESPACE}" \
    --values certs/uaa-cert-values.yaml \
    "${HELM_PARAMS[@]}"

# Deploy CF
kubectl create namespace "${CF_NAMESPACE}"
helm install s3.scf-config/helm/cf/ \
    --namespace "${CF_NAMESPACE}" \
    --values certs/scf-cert-values.yaml \
    --set "env.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "blobstore.disk_sizes.blobstore_data=50" \
    ${HELM_PARAMS[@]}

# Wait until CF is ready
is_namespace_pending() {
    local namespace="$1"
    if kubectl get pods --namespace="${namespace}" --output=custom-columns=':.status.conditions[?(@.type == "Ready")].status' | grep --silent False ; then
        return 0
    fi
    return 1
}
for namespace in "${UAA_NAMESPACE}" "${CF_NAMESPACE}" ; do
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
done
