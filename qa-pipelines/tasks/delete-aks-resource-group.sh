#!/bin/bash
set -o errexit
set -o nounset

AZ_RG_NAME=${PIPELINE_NAME}

az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID}
az group delete -n ${AZ_RG_NAME}
