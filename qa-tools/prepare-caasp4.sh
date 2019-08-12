#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Takes a newly deployed Caasp4 cluster, provided by the kubeconfig, and prepares it for CAP
  Usage: $0 --public-ip PUBLIC-IP --rootfs ROOTFS --nfs-server-ip NFS-SERVER-IP --nfs-path NFS-PATH"
}

create_configmap() {
    # Create configmap
    if kubectl get configmap -n kube-system 2>/dev/null | grep -qi cap-values; then
        echo "Skipping creating configmap cap-values; already exists"
    else
        echo "Creating configmap cap-values"
        # TODO: check if -i and -it are really needed in the following 3 commands
        kubectl create configmap -n kube-system cap-values \
          --from-literal=public-ip="${PUBLIC_IP}" \
          --from-literal=garden-rootfs-driver="${ROOTFS}" \
          --from-literal=nfs-server="${NFS_SERVER_IP}" \
          --from-literal=platform=caasp4
    fi
}

create_rolebinding() {
    cat cluster-admin.yaml | kubectl apply -f -
}

install_helm_and_tiller() {
    # install helm & tiller
    if kubectl get pods --all-namespaces 2>/dev/null | grep -qi tiller; then
        echo "Installing helm client"
         helm init --client-only
    else
        echo "Installing helm client and tiller"
        kubectl create serviceaccount tiller --namespace kube-system
        helm init
    fi
}

create_nfs_storageclass() {
    # Create nfs storageclass with provided nfs server
    if kubectl get storageclass 2>/dev/null | grep -qi persistent; then
        echo "Skipping setting up storageclass \"persistent\"; already exists"
    else
        echo "Creating storage class with provided nfs server"
        helm install stable/nfs-client-provisioner --set nfs.server="$NFS_SERVER_IP" --set nfs.path="$NFS_PATH"
    fi
}

create_qa_sa_config() {
    echo "Ensure the following config contents are in the lockfile for your concourse pool kube resource:"
    echo "---"
    # TODO
    bash "./create-qa-config.sh" | awk '/apiVersion/ { yaml=1 }  yaml { print }'
}


while [[ $# -gt 0 ]] ; do
    case $1 in
        --public-ip)
            PUBLIC_IP="$2"
            ;;
        --rootfs)
            ROOTFS="$2"
            ;;
        --nfs-server-ip)
            NFS_SERVER_IP="$2"
            ;;
        --nfs-path)
            NFS_PATH="$2"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
    esac
    shift
done

create_configmap
create_rolebinding
install_helm_and_tiller
create_nfs_storageclass
create_qa_sa_config
