#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
cp pool.kube-hosts/metadata /root/.kube/config

set -o allexport
CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
set +o allexport

for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
    for name in $(helm list --deployed --short --namespace "${namespace}") ; do
        helm delete "${name}" || true
    done
    while kubectl get namespace "${namespace}" ; do
        kubectl delete namespace "${namespace}" || true
        sleep 10
    done
done
