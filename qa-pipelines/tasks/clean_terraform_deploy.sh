#!/bin/bash
set -o errexit
set -o nounset

# usage: read_yaml_key test.yaml key-name
read_yaml_key() {
    ruby -r yaml -e "puts YAML.load_file('$1')[\"$2\"]"
}

AZURE_DNS_ZONE_NAME=susecap.net
AZURE_DNS_RESOURCE_GROUP=susecap-domain

azure_dns_clear() {
    local AZURE_AKS_RESOURCE_GROUP=$1
    local matching_record_sets matching_record_set
    matching_record_sets=$(
        az network dns record-set a list \
            --output tsv \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --query "[?name | ends_with(@, '.${AZURE_AKS_RESOURCE_GROUP}')].name" -o tsv
    )
    matching_record_sets="${matching_record_sets} ${AZURE_AKS_RESOURCE_GROUP}"
    for matching_record_set in ${matching_record_sets}; do
        echo "${matching_record_set}"
        az network dns record-set a delete \
            --yes \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --name ${matching_record_set}
    done
}

if [[ ${terraform_platform} == "aks" ]]; then
    CLUSTER_NAME=$(cat pool.kube-hosts/name)
    az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
    echo "Deleting az group ${CLUSTER_NAME} ..."
    az group delete -n ${CLUSTER_NAME} -y
    echo "az group ${CLUSTER_NAME} deleted"
fi
if [[ ${terraform_platform} == "gke" ]]; then
    base64 -d <<< "${GKE_PRIVATE_KEY_BASE64}" > gke-key.json
    export CLUSTER_NAME=$(cat pool.kube-hosts/name)
    pool_file=${pool_file:-pool.kube-hosts/metadata}
    export GKE_CLUSTER_ZONE=$(read_yaml_key ${pool_file} cluster-zone)
    gcloud auth activate-service-account --key-file=gke-key.json
    PROJECT=$(jq -r .project_id gke-key.json)
    gcloud config set project ${PROJECT}
    gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE}
    gcloud -q container clusters delete ${CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE}
    echo "Pruning all the PV disks attached to the cluster ... "
    filter=$(echo ${CLUSTER_NAME} | cut -c1-18)
    gcloud -q compute disks delete --zone ${GKE_CLUSTER_ZONE} $(gcloud compute disks list --filter="name~'${filter}'" | grep concourse-gke- | awk '{ print $1 }')
fi
echo "Deleting dns ..."
az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
azure_dns_clear ${CLUSTER_NAME}
echo "Deleted dns"
