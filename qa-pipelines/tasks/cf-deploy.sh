#!/bin/bash
set -o errexit

if [[ $ENABLE_CF_DEPLOY != true ]] && [[ $ENABLE_CF_DEPLOY_PRE_UPGRADE != true ]]; then
  echo "cf-deploy.sh: Flag not set. Skipping deploy"
  exit 0
fi

set -o nounset

source "ci/qa-pipelines/tasks/lib/cf-deploy-upgrade-common.sh"

set_helm_params # Sets HELM_PARAMS
set_uaa_sizing_params # Adds uaa sizing params to HELM_PARAMS

# Delete legacy psp/crb, and set up new psps, crs, and necessary crbs for CAP version
kubectl delete psp --ignore-not-found suse.cap.psp
kubectl delete clusterrolebinding --ignore-not-found cap:clusterrole
if semver_is_gte $(helm_chart_version) 2.15.1; then
    kubectl delete --ignore-not-found --filename=ci/qa-tools/cap-{psp-{,non}privileged,cr-privileged-2.14.5}.yaml
    kubectl apply --filename ci/qa-tools/cap-cr-privileged-2.15.1.yaml
else
    kubectl replace --force --filename=ci/qa-tools/cap-{psp-privileged,psp-nonprivileged,cr-privileged-2.14.5,crb-tests}.yaml
fi

kubectl replace --force --filename=ci/qa-tools/cap-crb-tests.yaml

if semver_is_gte $(helm_chart_version) 2.14.5; then
    kubectl delete --ignore-not-found --filename ci/qa-tools/cap-crb-2.13.3.yaml
else
    kubectl replace --filename ci/qa-tools/cap-crb-2.13.3.yaml
fi

echo UAA customization ...
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

# Deploy UAA
kubectl create namespace "${UAA_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${UAA_NAMESPACE}/g" | kubectl create -f -
fi

helm install ${CAP_DIRECTORY}/helm/uaa/ \
    --namespace "${UAA_NAMESPACE}" \
    --name uaa \
    --timeout 600 \
    "${HELM_PARAMS[@]}"

# Wait for UAA release
wait_for_release uaa

if [[ ${cap_platform} == "azure" ]]; then
    az_login
    azure_dns_clear
    azure_wait_for_lbs_in_namespace uaa
    azure_set_record_sets_for_namespace uaa
fi

# Deploy CF
CA_CERT="$(get_internal_ca_cert)"

set_helm_params # Resets HELM_PARAMS
set_scf_sizing_params # Adds scf sizing params to HELM_PARAMS

echo SCF customization ...
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

kubectl create namespace "${CF_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${CF_NAMESPACE}/g" | kubectl create -f -
fi

helm install ${CAP_DIRECTORY}/helm/cf/ \
    --namespace "${CF_NAMESPACE}" \
    --name scf \
    --timeout 600 \
    --set "secrets.CLUSTER_ADMIN_PASSWORD=${CLUSTER_ADMIN_PASSWORD:-changeme}" \
    --set "env.UAA_HOST=${UAA_HOST}" \
    --set "env.UAA_PORT=${UAA_PORT}" \
    --set "secrets.UAA_CA_CERT=${CA_CERT}" \
    "${HELM_PARAMS[@]}"

# Wait for CF release
wait_for_release scf

if [[ ${cap_platform} == "azure" ]]; then
    azure_wait_for_lbs_in_namespace scf
    azure_set_record_sets_for_namespace scf
fi
