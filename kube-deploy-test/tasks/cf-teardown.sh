#!/bin/bash

set -ex

#export k8s-host details from pool
set -a; source pool.k8s-hosts/metadata; set +a

ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
ssh -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP} 'kubectl delete namespace uaa; kubectl delete namespace cf'
