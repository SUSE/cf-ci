#!/bin/bash
set -o errexit
set -o nounset

az_resource_group=$(cat pool.kube-hosts/name)
az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
echo "Deleting az group ${az_resource_group} ..."
az group delete -n ${az_resource_group} -y
echo "az group ${az_resource_group} deleted"
