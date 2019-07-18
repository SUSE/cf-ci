#!/bin/bash
set -o errexit
set -o nounset

random_variable=$(hexdump -n 8 -e '2/4 "%08x"' /dev/urandom)
export TF_VAR_az_resource_group=concourse-tf-${random_variable}
export TF_VAR_cluster_labels="{\"owner\":\"${TF_VAR_az_resource_group}\"}"
az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
az group create --name ${TF_VAR_az_resource_group} --location ${TF_VAR_location} > /dev/null

helm init --client-only

cd ci/cap-terraform/aks/
terraform init
echo "Terraform plan in progress ..."
terraform plan > /dev/null
echo "Terraform apply in progress ..."
if ! terraform apply -auto-approve > /dev/null; then
    echo "Deleting az group ${TF_VAR_az_resource_group} ..."
    az group delete -n ${TF_VAR_az_resource_group} -y
    echo "az group ${TF_VAR_az_resource_group} deleted"
    exit 1
fi
echo "Terraform apply succeeded"
export KUBECONFIG=kubeconfig
kubectl get pods --all-namespaces
kubectl create configmap -n kube-system cap-values \
  --from-literal=platform=azure \
  --from-literal=resource-group=${TF_VAR_az_resource_group} \
  --from-literal=garden-rootfs-driver=overlay-xfs
cp kubeconfig ../../../kubeconfig-pool/metadata
echo ${TF_VAR_az_resource_group} > ../../../kubeconfig-pool/name
