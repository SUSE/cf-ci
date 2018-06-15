#!/bin/bash
set -o errexit -o nounset

if [[ $ENABLE_CF_TEARDOWN != true ]]; then
  echo "cf-teardown.sh: Flag not set. Skipping teardown"
  exit 0
fi

# Set kube config from pool
mkdir -p /root/.kube/
cp pool.kube-hosts/metadata /root/.kube/config

set -o allexport
CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
set +o allexport

for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
    while [[ $(kubectl get statefulsets --output json --namespace "${namespace}" | jq '.items | length == 0') != "true" ]]; do
      kubectl delete statefulsets --all --namespace "${namespace}" ||:
    done
    while kubectl get namespace "${namespace}" 2>/dev/null; do
      kubectl delete namespace "${namespace}" ||:
      sleep 30
    done
    while [[ -n $(helm list --short --all ${namespace}) ]]; do
        helm delete --purge ${namespace} ||:
        sleep 10
    done
done
