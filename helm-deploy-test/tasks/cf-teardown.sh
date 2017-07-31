#!/bin/bash

set -ex

#export k8s-host details from pool
set -a; source pool.k8s-hosts/metadata; set +a

#target the kube cluster
ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
kubectl config set-cluster --server=${K8S_HOST_IP}:${K8S_HOST_PORT} ${K8S_HOSTNAME}
kubectl config set-context ${K8S_HOSTNAME} --cluster=${K8S_HOSTNAME}
kubectl config use-context ${K8S_HOSTNAME}

ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
kubectl delete namespace uaa; kubectl delete namespace cf
for release in $(helm list | tail -n +2 | awk '{print $1}'); do helm delete $release || true; done
