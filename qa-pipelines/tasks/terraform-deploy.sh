#!/bin/bash
set -o errexit
set -o nounset

az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
az group create --name ${PIPELINE_NAME} --location ${TF_VAR_location} > /dev/null

helm init --client-only

(
cd ci/cap-terraform/aks/
terraform init
echo "Terraform plan in progress ..."
terraform plan > /dev/null
echo "Terraform apply in progress ..."
terraform apply -auto-approve > /dev/null
echo "Terraform apply succeeded"
)

git clone cf-ci-pools cf-ci-pools-terraform
cd cf-ci-pools-terraform
cp ../ci/cap-terraform/aks/aksk8scfg ${KUBE_POOL_POOL}/unclaimed/${PIPELINE_NAME}
git add ${KUBE_POOL_POOL}/unclaimed/${PIPELINE_NAME}
git commit -m "add ${PIPELINE_NAME}"
