#!/usr/bin/env bash
set -euo pipefail


# Takes a newly deployed Caasp4 cluster, provided by the kubeconfig, and prepares
# it for CAP
#
# Expected env var           Eg:
#   PUBLIC_IP                public ip of the caasp4 cluster, normally LB
#   NFS_SERVER_IP            ip of nfs server
#   NFS_PATH                 exported path of nfs server
#   ROOTFS                   btrfs, default overlay-xfs

if [[ ! -v ROOTFS ]]; then
    ROOTFS="overlay-xfs"
fi


create_configmap() {
    # Create configmap
    if kubectl get configmap -n kube-system 2>/dev/null | grep -qi cap-values; then
        echo ">>> Skipping creating configmap cap-values; already exists"
    else
        echo ">>> Creating configmap cap-values"
        kubectl create configmap -n kube-system cap-values \
          --from-literal=public-ip="${PUBLIC_IP}" \
          --from-literal=garden-rootfs-driver="${ROOTFS}" \
          --from-literal=nfs-server="${NFS_SERVER_IP}" \
          --from-literal=platform=caasp4
    fi
}

create_rolebinding() {
    kubectl apply -f - < cluster-admin.yaml
}

install_helm_and_tiller() {
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
        helm install stable/nfs-client-provisioner --set nfs.server="$NFS_SERVER_IP" --set nfs.path="$NFS_PATH" --set storageClass.name=persistent
    fi
}

create_qa_sa_config() {
    echo ">>> Ensure the following config contents are in the lockfile for your concourse pool kube resource:"
    echo "---"
    # TODO server this more graciously. Maybe append to preexisting kubeconfig
    bash "./create-qa-config.sh" | awk '/apiVersion/ { yaml=1 }  yaml { print }'
}

create_configmap
create_rolebinding
install_helm_and_tiller
create_nfs_storageclass
create_qa_sa_config

# TODO provide with helm home
