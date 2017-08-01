#!/bin/bash

set -ex

#export kube-host details from pool
set -a; source pool.kube-hosts/metadata; set +a

#kube-ready-state-check script
curl -O https://raw.githubusercontent.com/SUSE/scf/develop/bin/dev/kube-ready-state-check.sh

#check kube host readiness to deploy CF
sshpass -e ssh -o StrictHostKeyChecking=no "${K8S_USER}@${K8S_HOST_IP}" -- \
    bash -s < kube-ready-state-check.sh

#target the kube cluster
kubectl config set-cluster --server=http://${K8S_HOST_IP}:${K8S_HOST_PORT} ${K8S_HOSTNAME}
kubectl config set-context ${K8S_HOSTNAME} --cluster=${K8S_HOSTNAME}
kubectl config use-context ${K8S_HOSTNAME}

unzip s3.scf-config.linux/scf-linux-amd64-* -d scf-config

#Certs generation
mkdir certs
pushd scf-config
./cert-generator.sh -d ${DOMAIN} -n cf -o ../certs
popd

#Deploy UAA
kubectl create namespace uaa
helm install scf-config/helm/uaa \
     --set kube.storage_class.persistent=${STORAGECLASS} \
     --namespace "uaa" \
     --values certs/uaa-cert-values.yaml \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "kube.external_ip=${K8S_HOST_IP}"

#Deploy CF
kubectl create namespace cf
helm install scf-config/helm/cf \
     --set kube.storage_class.persistent=${STORAGECLASS} \
     --namespace "cf" \
     --values certs/scf-cert-values.yaml \
     --set "env.CLUSTER_ADMIN_PASSWORD=$CLUSTER_ADMIN_PASSWORD" \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "env.UAA_HOST=${UAA_HOST}" \
     --set "env.UAA_PORT=${UAA_PORT}" \
     --set "kube.external_ip=${K8S_HOST_IP}"
