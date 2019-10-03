#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
source "ci/qa-pipelines/tasks/lib/prepare-kubeconfig.sh"
source "ci/qa-pipelines/tasks/lib/klog-collection.sh"

set -o allexport
CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
set +o allexport

namespaces=("${CF_NAMESPACE}" "${UAA_NAMESPACE}")
if [[ "${EXTERNAL_DB:-false}" == "true" ]]; then
    namespaces+=( "external-db" )
fi
while [[ "${#namespaces[@]}" -gt 0 ]]; do
    # Upload klogs for any releases which have not yet been successfully deleted
    trap "upload_klogs_on_failure ${namespaces[*]}" EXIT
    while [[ -n $(helm list --short --all ${namespaces[0]}) ]]; do
        helm delete --purge ${namespaces[0]} ||:
        sleep 10
    done
    namespaces=(${namespaces[@]:1})
done
trap "" EXIT

for namespace in ${namespaces[@]} ; do
    while kubectl get namespace "${namespace}" 2>/dev/null; do
      kubectl delete namespace "${namespace}" ||:
      sleep 30
    done
    while [[ $(kubectl get statefulsets --output json --namespace "${namespace}" | jq '.items | length == 0') != "true" ]]; do
      kubectl delete statefulsets --all --namespace "${namespace}" ||:
    done
done

cap_platform=${cap_platform:-$(kubectl get configmap -n kube-system cap-values -o json | jq -r .data.platform)}

if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
    source "ci/qa-pipelines/tasks/lib/azure-aks.sh"
    az_login
    azure_dns_clear
fi

kubectl delete --ignore-not-found \
    --filename ci/qa-tools/cap-cr-privileged-2.14.5.yaml \
    --filename ci/qa-tools/cap-cr-privileged-2.15.1.yaml \
    --filename ci/qa-tools/cap-crb-2.13.3.yaml \
    --filename ci/qa-tools/cap-crb-tests.yaml \
    --filename ci/qa-tools/cap-psp-nonprivileged.yaml \
    --filename ci/qa-tools/cap-psp-privileged.yaml
