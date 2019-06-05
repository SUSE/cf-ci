#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
source "ci/qa-pipelines/tasks/lib/prepare-kubeconfig.sh"
set -o allexport
CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
set +o allexport

for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
    while [[ -n $(helm list --short --all ${namespace}) ]]; do
        helm delete --purge ${namespace} ||:
        sleep 10
    done
done

for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
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
