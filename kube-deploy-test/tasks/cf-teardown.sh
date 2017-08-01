#!/bin/bash

set -e

#export k8s-host details from pool
set -a; source pool.kube-hosts/metadata; set +a

sshpass -e ssh -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP} 'kubectl delete namespace uaa; kubectl delete namespace cf'
