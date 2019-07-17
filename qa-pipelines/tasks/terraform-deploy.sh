#!/bin/bash
set -o errexit
set -o nounset

AZ_RG_NAME=${PIPELINE_NAME}
az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} &> /dev/null
az group create --name ${AZ_RG_NAME} --location ${AZ_REGION} &> /dev/null

cd ci/cap-terraform/aks/
terraform init &> /dev/null
terraform plan &> /dev/null
terraform apply -auto-approve &> /dev/null
git clone ${KUBE_POOL_REPO}
cd ${KUBE_POOL_BRANCH}
git checkout -t origin/${KUBE_POOL_BRANCH}
cp ../aksk8scfg unclaimed/${PIPELINE_NAME}
git add unclaimed/${PIPELINE_NAME}
git commit -m "add ${PIPELINE_NAME}"
git push
