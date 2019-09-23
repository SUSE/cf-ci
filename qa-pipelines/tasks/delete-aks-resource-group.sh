#!/bin/bash
set -o errexit
set -o nounset

AZURE_DNS_ZONE_NAME=susecap.net
AZURE_DNS_RESOURCE_GROUP=susecap-domain

azure_dns_clear() {
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

az_resource_group=$(cat pool.kube-hosts/name)
az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
echo "Deleting az group ${az_resource_group} ..."
az group delete -n ${az_resource_group} -y
echo "az group ${az_resource_group} deleted"
echo "Deleting dns ..."
AZURE_AKS_RESOURCE_GROUP=${az_resource_group}
azure_dns_clear
echo "Deleted dns ..."
