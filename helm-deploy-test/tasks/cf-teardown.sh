#!/bin/bash

set -o errexit -o nounset

# Export kube-host details from pool
set -o allexport
source pool.kube-hosts/metadata
CF_NAMESPACE=cf
UAA_NAMESPACE=uaa
set +o allexport

# Connect to Kubernetes
bash -x ci/helm-deploy-test/tasks/common/connect-kube-host.sh

for namespace in "$CF_NAMESPACE" "$UAA_NAMESPACE" ; do
    for name in $(helm list --deployed --short --namespace "${namespace}") ; do
        helm delete "${name}" || true
    done
    while kubectl get namespace "${namespace}" ; do
        kubectl delete namespace "${namespace}" || true
        sleep 10
    done
done
