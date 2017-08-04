#!/bin/bash

set -o errexit -o nounset

# Export kube-host details from pool
set -o allexport
source pool.kube-hosts/metadata
CF_NAMESPACE=cf
UAA_NAMESPACE=uaa
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"
set +o allexport

# Connect to Kubernetes
bash -x ci/helm-deploy-test/tasks/common/connect-kube-host.sh

unzip s3.scf-config/scf-linux-*.zip -d s3.scf-config/

# Check that the cluster is reasonable
if test -n "${K8S_USER:-}" -a -n "${SSHPASS:-}" ; then
    sshpass -e ssh -o StrictHostKeyChecking=no "${K8S_USER}@${K8S_HOST_IP}" -- \
        bash -s < s3.scf-config/kube-ready-state-check.sh
else
    printf "%bWarning: SSH password not supplied, not checking cluster sanity%b\n" \
        "\033[0;33;1m" "\033[0m" >&2
fi

# Generate certificates
mkdir certs/
pushd s3.scf-config/
./cert-generator.sh -d "${DOMAIN}" -n "${CF_NAMESPACE}" -o ../certs/
popd

# Deploy UAA
kubectl create namespace "${UAA_NAMESPACE}"
helm install s3.scf-config/helm/uaa/ \
    --namespace "${UAA_NAMESPACE}" \
    --values certs/uaa-cert-values.yaml \
    --set "env.DOMAIN=${DOMAIN}" \
    --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
    --set "kube.external_ip=${K8S_HOST_IP}"

# Deploy CF
kubectl create namespace "${CF_NAMESPACE}"
helm install s3.scf-config/helm/cf/ \
    --namespace "${CF_NAMESPACE}" \
    --values certs/scf-cert-values.yaml \
    --set "env.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.DOMAIN=${DOMAIN}" \
    --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
    --set "env.UAA_HOST=uaa.${DOMAIN}" \
    --set "env.UAA_PORT=2793" \
    --set "kube.external_ip=${K8S_HOST_IP}"

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
    for (( i = 0  ; i < 240 ; i ++ )) ; do
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
