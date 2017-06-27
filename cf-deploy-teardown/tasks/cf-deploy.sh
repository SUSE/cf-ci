#!/bin/bash

set -ex

env
# Run the following commands in an environment with kubectl to target this kube cluster:
kubectl config set-cluster --server=$K8S_HOST_IP $K8S_HOSTNAME
kubectl config set-context $K8S_HOSTNAME --cluster=$K8S_HOSTNAME
kubectl config use-context $K8S_HOSTNAME

unzip s3.scf-kube-yml/scf-kube-* -d scf-kube-yml

#Deploy UAA
kubectl create namespace uaa
kubectl create -n uaa -f s3.scf-kube-yml/uaa/bosh/
kubectl create -n uaa -f s3.scf-kube-yml/uaa/kube-test/exposed-ports.yml

#Deploy CF
kubectl create namespace cf
kubectl create -n cf -f s3.scf-kube-yml/bosh
kubectl create -n cf -f s3.scf-kube-yml/bosh-task/post-deployment-setup.yml
