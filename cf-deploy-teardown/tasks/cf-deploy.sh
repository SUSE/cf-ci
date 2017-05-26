#!/bin/bash

set -ex

tar xf s3.kube-config-yml/hcf-kube-*

#Deploy UAA
#kubectl create namespace uaa
#kubectl create -n uaa -f s3.uaa-config-yml/bosh/
#kubectl create -n uaa -f s3.uaa-config-yml/kube-test/exposed-ports.yml

#Deploy CF
kubectl create namespace cf
kubectl create -n cf -f s3.kube-config-yml/bosh
kubectl create -n cf -f s3.kube-config-yml/bosh-task/post-deployment-setup.yml
