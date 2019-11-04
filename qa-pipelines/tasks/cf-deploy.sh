#!/bin/bash
set -o errexit
set -o nounset

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"
source "ci/qa-pipelines/tasks/lib/klog-collection.sh"

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


#set_helm_params # Sets HELM_PARAMS.
#set_uaa_params # Adds uaa specific params to HELM_PARAMS.

#echo "UAA customization..."
#echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

if [[ "${EMBEDDED_UAA:-false}" != "true" ]]; then
    # Deploy UAA.
    kubectl create namespace "${UAA_NAMESPACE}"
    if [[ "${PROVISIONER}" == "kubernetes.io/rbd" ]]; then
        kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${UAA_NAMESPACE}/g" | kubectl create -f -
    fi

    helm install ${CAP_DIRECTORY}/helm/uaa/ \
        --namespace "${UAA_NAMESPACE}" \
        --name uaa \
        --timeout 1200 \
        "${HELM_PARAMS[@]}"

    trap "upload_klogs_on_failure ${UAA_NAMESPACE}" EXIT

    # Wait for UAA release.
    wait_for_release uaa

    if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
        az_login
        azure_dns_clear
        azure_wait_for_lbs_in_namespace uaa
        azure_set_record_sets_for_namespace uaa
    fi
fi

# Deploy CF.
#set_helm_params # Resets HELM_PARAMS.
#set_scf_params # Adds scf specific params to HELM_PARAMS.

kubectl create namespace "${CF_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${CF_NAMESPACE}/g" | kubectl create -f -
fi

# When this deploy task is running in a deploy (non-upgrade) pipeline, the deploy is HA, and we want to test config.HA_strict:
if [[ "${HA}" == true ]] && [[ -n "${HA_STRICT:-}" ]] && [[ -z "${CAP_BUNDLE_URL:-}" ]]; then
    HELM_PARAMS+=(--set "config.HA_strict=${HA_STRICT}")
    HELM_PARAMS+=(--set "sizing.diego_api.count=1")
fi

echo "SCF customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

# helm install ${CAP_DIRECTORY}/helm/cf/ \
#     --namespace "${CF_NAMESPACE}" \
#     --name scf \
#     --timeout 1200 \
#     --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
#     --set "env.UAA_HOST=${UAA_HOST}" \
#     --set "env.UAA_PORT=${UAA_PORT}" \
#     --set "env.SCF_LOG_HOST=${SCF_LOG_HOST}" \
#     --set "env.INSECURE_DOCKER_REGISTRIES=${INSECURE_DOCKER_REGISTRIES}" \
#     "${HELM_PARAMS[@]}"
helm install --name cf-operator \
     --namespace cfo \
     --set "operator.watchNamespace=kubecf" \
     ${CF_OPERATOR_DIRECTORY}

helm install --name kubecf \
     --namespace "${CF_NAMESPACE}" \
     ${CAP_DIRECTORY} \
     --set "system_domain=${DOMAIN}"

trap "upload_klogs_on_failure ${UAA_NAMESPACE} ${CF_NAMESPACE}" EXIT

if [[ "${EMBEDDED_UAA:-false}" == "true" ]]; then
    if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
        az_login
        azure_dns_clear
        azure_wait_for_lbs_in_namespace scf 'select(.metadata.name=="uaa-uaa-public")'
        azure_set_record_sets_for_namespace scf 'select(.metadata.name=="uaa-uaa-public")'
    fi
fi

# Wait for CF release
wait_for_release scf

if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
    azure_wait_for_lbs_in_namespace scf
    azure_set_record_sets_for_namespace scf
fi

trap "" EXIT
