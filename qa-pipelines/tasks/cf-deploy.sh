#!/bin/bash
set -o errexit
set -o nounset

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"
source "ci/qa-pipelines/tasks/lib/klog-collection.sh"

pxc_pre_upgrade() {
    if [[ -n "${CAP_BUNDLE_URL:-}" ]] && [[ "${HA}" == true ]]; then
        if semver_is_gte 2.17.1 "$(helm_chart_version)"; then
            return 0    
        fi
        return 1
    fi
}

if pxc_pre_upgrade; then
   export SCALED_HA=0
fi

set_helm_params # Sets HELM_PARAMS
set_uaa_sizing_params # Adds uaa sizing params to HELM_PARAMS

# Delete legacy psp/crb, and set up new psps, crs, and necessary crbs for CAP version
kubectl delete psp --ignore-not-found suse.cap.psp
kubectl delete clusterrolebinding --ignore-not-found cap:clusterrole
if [[ ${cap_platform} != "eks" ]]; then
    if semver_is_gte "$(helm_chart_version)" 2.15.1; then
        kubectl delete --ignore-not-found --filename=ci/qa-tools/cap-{psp-{,non}privileged,cr-privileged-2.14.5}.yaml
        kubectl apply --filename ci/qa-tools/cap-cr-privileged-2.15.1.yaml
    else
        kubectl replace --force --filename=ci/qa-tools/cap-{psp-privileged,psp-nonprivileged,cr-privileged-2.14.5,crb-tests}.yaml
    fi

    kubectl replace --force --filename=ci/qa-tools/cap-crb-tests.yaml

    if semver_is_gte "$(helm_chart_version)" 2.14.5; then
        kubectl delete --ignore-not-found --filename ci/qa-tools/cap-crb-2.13.3.yaml
    else
        kubectl replace --filename ci/qa-tools/cap-crb-2.13.3.yaml
    fi
fi

echo "UAA customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

if [[ "${EMBEDDED_UAA:-false}" != "true" ]]; then
    # Deploy UAA
    kubectl create namespace "${UAA_NAMESPACE}"
    if [[ "${PROVISIONER}" == "kubernetes.io/rbd" ]]; then
        kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${UAA_NAMESPACE}/g" | kubectl create -f -
    fi

    helm install ${CAP_DIRECTORY}/helm/uaa/ \
        --namespace "${UAA_NAMESPACE}" \
        --name uaa \
        --timeout 600 \
        "${HELM_PARAMS[@]}"

    trap "upload_klogs_on_failure ${UAA_NAMESPACE}" EXIT

    # Wait for UAA release
    wait_for_release uaa

    if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
        az_login
        azure_dns_clear
        azure_wait_for_lbs_in_namespace uaa
        azure_set_record_sets_for_namespace uaa
    fi
fi

# Deploy CF
set_helm_params # Resets HELM_PARAMS
set_scf_sizing_params # Adds scf sizing params to HELM_PARAMS

echo "SCF customization..."
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

kubectl create namespace "${CF_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${CF_NAMESPACE}/g" | kubectl create -f -
fi

if [[ "${EMBEDDED_UAA:-false}" != "true" ]]; then
    HELM_PARAMS+=(--set "secrets.UAA_CA_CERT=$(get_uaa_ca_cert)")
fi

helm install ${CAP_DIRECTORY}/helm/cf/ \
    --namespace "${CF_NAMESPACE}" \
    --name scf \
    --timeout 600 \
    --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "env.SCF_LOG_HOST=${SCF_LOG_HOST}" \
    --set "env.INSECURE_DOCKER_REGISTRIES=${INSECURE_DOCKER_REGISTRIES}" \
    "${HELM_PARAMS[@]}"

trap "upload_klogs_on_failure ${UAA_NAMESPACE} ${CF_NAMESPACE}" EXIT

# Wait for CF release
wait_for_release scf

if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
    azure_wait_for_lbs_in_namespace scf
    azure_set_record_sets_for_namespace scf
fi

set_helm_params # Resets HELM_PARAMS

if pxc_pre_upgrade; then
    echo "Downsizing UAA mysql node count to 1..."
    helm upgrade --reuse-values uaa ${CAP_DIRECTORY}/helm/uaa/ \
        --namespace "${UAA_NAMESPACE}" \
        --timeout 600 \
        --set "sizing.mysql.count=1"

    # Wait for UAA release
    wait_for_release uaa

    echo "Downsizing SCF mysql node count to 1..."
    helm upgrade --reuse-values scf ${CAP_DIRECTORY}/helm/cf/ \
        --namespace "${CF_NAMESPACE}" \
        --timeout 3600 \
        --set "sizing.mysql.count=1"
    
    # Wait for CF release
    wait_for_release scf
fi

trap "" EXIT
