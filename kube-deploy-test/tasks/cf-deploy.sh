#!/bin/bash

set -ex

#export k8s-host details from pool
set -a; source pool.k8s-hosts/metadata; set +a

#kube-ready-state-check script
curl -O https://raw.githubusercontent.com/SUSE/scf/develop/bin/dev/kube-ready-state-check.sh

#check kube host readiness to deploy CF
ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
ssh -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP} 'bash -s' \
    < kube-ready-state-check.sh

#target the kube cluster
kubectl config set-cluster --server=http://${K8S_HOST_IP}:${K8S_HOST_PORT} ${K8S_HOSTNAME}
kubectl config set-context ${K8S_HOSTNAME} --cluster=${K8S_HOSTNAME}
kubectl config use-context ${K8S_HOSTNAME}

unzip s3.scf-config.linux/scf-linux-amd64-* -d scf-config

#Deploy UAA
kubectl create namespace uaa
kubectl create -n uaa -f scf-config/kube/uaa/bosh/
kubectl create -n uaa -f scf-config/kube/uaa/kube-test/exposed-ports.yml

#Deploy CF
kubectl create namespace cf
kubectl create -n cf -f scf-config/kube/cf/bosh
kubectl create -n cf -f scf-config/kube/cf/bosh-task/post-deployment-setup.yml
