#!/bin/bash

set -ex

unzip s3.uaa-kube-yml/uaa-kube-* -d uaa-kube-yml
unzip s3.hcf-kube-yml/hcf-kube-* -d hcf-kube-yml

#Deploy UAA
kubectl create namespace uaa
kubectl create -n uaa -f s3.uaa-kube-yml/bosh/

#Deploy CF
kubectl create namespace cf
kubectl create -n cf -f s3.hcf-kube-yml/bosh
kubectl create -n cf -f s3.hcf-kube-yml/bosh-task/post-deployment-setup.yml
