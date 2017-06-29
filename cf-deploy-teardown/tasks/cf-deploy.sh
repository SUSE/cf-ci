#!/bin/bash

set -ex

#check k8s host readiness to deploy CF
sshpass -p $K8S_PASSWORD  ssh $K8S_USER@$K8S_HOST_IP 'bash -s' < ci/cf-deploy-teardown/tasks/k8s-ready-state-check.sh

# target the kube cluster:
kubectl config set-cluster --server=$K8S_HOST_IP:$K8S_HOST_PORT $K8S_HOSTNAME
kubectl config set-context $K8S_HOSTNAME --cluster=$K8S_HOSTNAME
kubectl config use-context $K8S_HOSTNAME

unzip s3.scf-kube-yml/scf-kube-* -d scf-kube-yml

#Deploy UAA
kubectl create namespace uaa
kubectl create -n uaa -f scf-kube-yml/uaa/bosh/
kubectl create -n uaa -f scf-kube-yml/uaa/kube-test/exposed-ports.yml

#Deploy CF
kubectl create namespace cf
kubectl create -n cf -f scf-kube-yml/cf/bosh
kubectl create -n cf -f scf-kube-yml/cf/bosh-task/post-deployment-setup.yml
