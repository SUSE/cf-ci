#!/bin/bash
set -o errexit
set -o nounset

cleanup() {
    set +o errexit

    echo "Cleaning terraform bits ..."
    if [[ ${terraform_platform} == "aks" ]]; then
        az group delete -n ${TF_VAR_az_resource_group} -y
    fi
    if [[ ${terraform_platform} == "gke" ]]; then
        gcloud auth activate-service-account --key-file=gke-key.json
        gcloud config set project ${TF_VAR_project}
        gcloud container clusters get-credentials  ${TF_VAR_cluster_name} --zone ${TF_VAR_location}
        gcloud -q container clusters delete ${TF_VAR_cluster_name} --zone ${TF_VAR_location}
    fi
    echo "Terraform bits cleaned"

    set -o errexit
    exit 1
}
trap cleanup EXIT

random_variable=$(hexdump -n 8 -e '2/4 "%08x"' /dev/urandom)

helm init --client-only
if [[ ${terraform_platform} == "aks" ]]; then
    export TF_VAR_az_resource_group=concourse-aks-${random_variable}
    export TF_VAR_cluster_labels="{\"owner\":\"${TF_VAR_az_resource_group}\"}"
    az login --service-principal -u ${ARM_CLIENT_ID} --password ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID} > /dev/null
    az group create --name ${TF_VAR_az_resource_group} --location ${TF_VAR_location} > /dev/null
    cd ci/cap-terraform/aks/
fi

if [[ ${terraform_platform} == "gke" ]]; then
    cd ci/cap-terraform/gke/
    base64 -d <<< "${GKE_PRIVATE_KEY_BASE64}" > gke-key.json
    export TF_VAR_project=$(jq -r .project_id gke-key.json)
    export TF_VAR_gke_sa_key=gke-key.json
    export TF_VAR_node_pool_name=tf
    export TF_VAR_cluster_name=concourse-gke-${random_variable}
    export TF_VAR_cluster_labels="{\"owner\":\"${TF_VAR_cluster_name}\"}"
fi

terraform init
echo "Terraform plan in progress ..."
terraform plan > /dev/null
echo "Terraform apply in progress ..."
terraform apply -auto-approve > /dev/null
echo "Terraform apply succeeded"

if [[ ${terraform_platform} == "aks" ]]; then
    export KUBECONFIG=kubeconfig
    kubectl get pods --all-namespaces
    kubectl create configmap -n kube-system cap-values \
      --from-literal=platform=azure \
      --from-literal=resource-group=${TF_VAR_az_resource_group} \
      --from-literal=garden-rootfs-driver=overlay-xfs
    echo ${TF_VAR_az_resource_group} > ../../../kubeconfig-pool/name
fi
if [[ ${terraform_platform} == "gke" ]]; then
    cat << EOF > kubeconfig
---
kind: ClusterReference
platform: gke
cluster-name: ${TF_VAR_cluster_name}
cluster-zone: ${TF_VAR_location}
EOF
    kubectl get pods --all-namespaces
    kubectl create configmap -n kube-system cap-values \
      --from-literal=garden-rootfs-driver=overlay-xfs
    echo ${TF_VAR_cluster_name} > ../../../kubeconfig-pool/name
fi

cp kubeconfig ../../../kubeconfig-pool/metadata
trap "" EXIT
