#!/usr/bin/env bash
set -euo pipefail


# Takes a newly deployed Caasp4 cluster, provided by the kubeconfig, and prepares
# it for CAP
#
# Requires:
# kubectl & helm binaries


create_rolebinding() {
    echo ">>> Applying cluster admin RBACs"
    kubectl apply -f - < "$(dirname $0)"/cluster-admin.yaml
}

install_helm_and_tiller() {
    export HELM_HOME="$WORKSPACE"/.helm
    # install helm & tiller
    if kubectl get pods --all-namespaces 2>/dev/null | grep -qi tiller; then
        echo ">>> Installing helm client"
         helm init --client-only
    else
        echo ">>> Installing helm client and tiller"
        kubectl create serviceaccount tiller --namespace kube-system
        helm init --wait
    fi
    echo ">>> Installed helm successfully"
}

create_nfs_storageclass() {
    # Create nfs storageclass with provided nfs server
    if kubectl get storageclass 2>/dev/null | grep -qi persistent; then
        echo ">>> Skipping setting up storageclass \"persistent\"; already exists"
    else
        echo ">>> Creating storage class with provided nfs server"
        NFS_SERVER_IP=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["nfs-server-ip"]')
        NFS_PATH=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["nfs-path"]')
        helm install stable/nfs-client-provisioner --set nfs.server="$NFS_SERVER_IP" --set nfs.path="$NFS_PATH" \
             --set storageClass.name=persistent \
             --set storageClass.reclaimPolicy=Delete --set storageClass.archiveOnDelete=false
    fi
}

create_qa_sa_config() {
    echo ">>> Creating qa config"
    export WORKSPACE
    "$(dirname $0)"/create-qa-config.sh >/dev/null 2>&1
}

echo ">>> Preparing cluster for CAP"
create_rolebinding
install_helm_and_tiller
create_nfs_storageclass
create_qa_sa_config
echo ">>> Done preparing cluster for CAP"
