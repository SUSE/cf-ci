#!/bin/bash

set -e

#export k8s-host details from pool
set -a; source pool.k8s-hosts/metadata; set +a

#check k8s host readiness to deploy CF
ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
ssh -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP} 'bash -s' < cf-ci/cf-deploy-test-teardown/tasks/k8s-ready-state-check.sh

#target the kube cluster
kubectl config set-cluster --server=${K8S_HOST_IP}:${K8S_HOST_PORT} ${K8S_HOSTNAME}
kubectl config set-context ${K8S_HOSTNAME} --cluster=${K8S_HOSTNAME}
kubectl config use-context ${K8S_HOSTNAME}

unzip s3.scf-kube-yml/scf-kube-* -d scf-kube-yml
unzip s3.scf-helm-charts/hcf-kube-charts-* -d scf-helm-charts

#Deploy UAA
kubectl create namespace uaa
#kubectl create -n uaa -f scf-kube-yml/uaa/bosh/
#kubectl create -n uaa -f scf-kube-yml/uaa/kube-test/exposed-ports.yml
helm install scf-helm-charts/uaa/helm \
     --namespace "uaa" \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "kube.external_ip=${K8S_HOST_IP}"


#Deploy CF
kubectl create namespace cf
#kubectl create -n cf -f scf-kube-yml/cf/bosh
#kubectl create -n cf -f scf-kube-yml/cf/bosh-task/post-deployment-setup.yml
helm install scf-helm-charts/cf/helm \
     --namespace "cf" \
     --set "env.CLUSTER_ADMIN_PASSWORD=$CLUSTER_ADMIN_PASSWORD" \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "env.UAA_HOST=${UAA_HOST}" \
     --set "env.UAA_PORT=${UAA_PORT}" \
     --set "kube.external_ip=${K8S_HOST_IP}"
