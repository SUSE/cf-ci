#!/bin/bash
set -o errexit
set -o nounset

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"
#source "ci/qa-pipelines/tasks/lib/klog-collection.sh"

# Delete legacy psp/crb, and set up new psps, crs, and necessary crbs for CAP version
kubectl delete psp --ignore-not-found suse.cap.psp
kubectl delete clusterrolebinding --ignore-not-found cap:clusterrole
if [[ ${cap_platform} != "eks" ]]; then
    kubectl apply --filename ci/qa-tools/cap-cr-privileged-2.15.1.yaml
    kubectl replace --force --filename=ci/qa-tools/cap-crb-tests.yaml
fi

# external db for uaa and scf db
if [[ "${EXTERNAL_DB:-false}" == "true" ]]; then
    helm init --client-only
    helm repo add stable https://kubernetes-charts.storage.googleapis.com
    helm install stable/mariadb \
        --version 6.10.1 \
        --name external-db \
        --namespace external-db \
        --set volumePermissions.enabled=true
    kubectl wait --timeout=10m --namespace external-db --for=condition=ready pod/external-db-mariadb-master-0
    export EXTERNAL_DB_PASS="$(kubectl get secret -n external-db external-db-mariadb -o jsonpath='{.data.mariadb-root-password}' | base64 --decode)"
fi

helm install ${CAP_DIRECTORY}/cf-operator-*.tgz \
    --namespace "${CFO_NAMESPACE}" \
    --name cfo \
    --set global.operator.watchNamespace="${CF_NAMESPACE}" \
    --timeout 1200

# Wait for cfo release.
kubectl wait --timeout=10m --namespace "${CFO_NAMESPACE}" --for=condition=ready pod --all
helm list
kubectl get ns
kubectl get pods --namespace "${CFO_NAMESPACE}"

# Deploy CF.
# set_helm_params # Resets HELM_PARAMS.
set_kubecf_params # Adds scf specific params to HELM_PARAMS.

#kubectl create namespace "${CF_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${CF_NAMESPACE}/g" | kubectl create -f -
fi

echo "kubecf customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

helm install ${CAP_DIRECTORY}/kubecf-*.tgz \
    --namespace "${CF_NAMESPACE}" \
    --name kubecf \
    --timeout 1200 \
    "${HELM_PARAMS[@]}"

#trap "upload_klogs_on_failure ${UAA_NAMESPACE} ${CF_NAMESPACE}" EXIT

# if [[ "${EMBEDDED_UAA:-false}" == "true" ]]; then
if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
    az_login
    azure_dns_clear
    azure_wait_for_lbs_in_namespace scf 'select(.metadata.name=="uaa-uaa-public")'
    azure_set_record_sets_for_namespace scf 'select(.metadata.name=="uaa-uaa-public")'
fi
# fi

# Wait for CF release
wait_for_release kubecf

if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
    azure_wait_for_lbs_in_namespace scf
    azure_set_record_sets_for_namespace scf
fi

trap "" EXIT
