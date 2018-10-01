#!/bin/bash
set -o errexit

if [[ $ENABLE_CF_DEPLOY != true ]] && [[ $ENABLE_CF_DEPLOY_PRE_UPGRADE != true ]]; then
  echo "cf-deploy.sh: Flag not set. Skipping deploy"
  exit 0
fi

set -o nounset

source "ci/qa-pipelines/tasks/cf-deploy-upgrade-common.sh"

set_helm_params # Sets HELM_PARAMS
set_uaa_sizing_params # Adds uaa sizing params to HELM_PARAMS

echo UAA customization ...
echo "${HELM_PARAMS[@]}" | sed 's/kube\.registry\.password=[^[:space:]]*/kube.registry.password=<REDACTED>/g'

# Deploy UAA
kubectl create namespace "${UAA_NAMESPACE}"
if [[ ${PROVISIONER} == kubernetes.io/rbd ]]; then
    kubectl get secret -o yaml ceph-secret-admin | sed "s/namespace: default/namespace: ${UAA_NAMESPACE}/g" | kubectl create -f -
fi

helm install ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/ \
    --namespace "${UAA_NAMESPACE}" \
    --name uaa \
    --timeout 600 \
    "${HELM_PARAMS[@]}"

# Wait for UAA release
wait_for_release uaa

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

helm install ${CAP_DIRECTORY}/helm/cf${CAP_CHART}/ \
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

if [[ $(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data.platform') == "azure" ]]; then
    keys=( $(kubectl get configmap -n kube-system custom-broker-args -o json | jq -r '.data | keys[]') )
    cd $(mktemp -d)
    git clone https://github.com/Azure/open-service-broker-azure
    cd open-service-broker-azure
    for key in "${keys[@]}"; do
        sed -i "s/${key}:.*/${key}: $(kubectl get configmap -n kube-system custom-broker-args -o json | jq -r ".data.${key}")/" contrib/cf/manifest.yml
    done
    cf api --skip-ssl-validation "https://api.${DOMAIN}"
    cf login -u admin -p changeme -o system
    cf create-org osba-org
    cf create-space -o osba-org osba-space
    cf target -o osba-org -s osba-space
    cf push -f contrib/cf/manifest.yml
    cf create-service-broker open-service-broker-azure username password https://osba.$DOMAIN
fi
