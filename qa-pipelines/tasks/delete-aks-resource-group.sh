#!/bin/bash
set -o errexit
set -o nounset

az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
az group delete -n ${PIPELINE_NAME}
echo "az group ${PIPELINE_NAME} deleted"
