#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

set -o allexport
CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
set +o allexport

for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
    kubectl delete namespace "${namespace}"
    while [[ -n $(helm list --short --all ${namespace}) ]]; do
        sleep 10
        helm delete --purge ${namespace} ||:
    done
done
