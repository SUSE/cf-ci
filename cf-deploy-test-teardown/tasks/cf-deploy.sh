#!/bin/bash

set -ex



#NOTES:
export HELM_VERSION="2.4.2"
bin_dir="${bin_dir:-/usr/local/bin/}"
helm_url="${helm_url:-https://kubernetes-helm.storage.googleapis.com/helm-v${HELM_VERSION}-linux-amd64.tar.gz}"
#zypper --non-interactive addrepo http://download.opensuse.org/repositories/Virtualization:containers/openSUSE_Leap_42.2/Virtualization:containers.repo
#zypper  --non-interactive --gpg-auto-import-keys refresh
#mkdir -p "${bin_dir}"
#bin_dir="$(cd "${bin_dir}" && pwd)"
zypper --non-interactive install wget
zypper --non-interactive install tar
wget -q "${helm_url}" -O - | tar xz -C "${bin_dir}" --strip-components=1 linux-amd64/helm
chmod a+x "${bin_dir}/helm"


#export k8s-host details from pool
set -a; source pool.k8s-hosts/metadata; set +a

#check k8s host readiness to deploy CF
ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
ssh -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP} 'bash -s' < cf-ci/cf-deploy-test-teardown/tasks/k8s-ready-state-check.sh

#target the kube cluster
kubectl config set-cluster --server=http://${K8S_HOST_IP}:${K8S_HOST_PORT} ${K8S_HOSTNAME}
kubectl config set-context ${K8S_HOSTNAME} --cluster=${K8S_HOSTNAME}
kubectl config use-context ${K8S_HOSTNAME}

#Tiller needs to be on k8shost and must not be part of this script
# helm init
# sleep 60

unzip s3.scf-alpha/scf-linux-amd64-1.8.8-* -d scf-alpha
#unzip s3.scf-helm-charts/hcf-kube-charts-* -d scf-helm-charts


#Deploy UAA
kubectl create namespace uaa
#kubectl create -n uaa -f scf-kube-yml/uaa/bosh/
#kubectl create -n uaa -f scf-kube-yml/uaa/kube-test/exposed-ports.yml
helm install scf-alpha/helm/uaa \
     --namespace "uaa" \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "kube.external_ip=${K8S_HOST_IP}"


#Deploy CF
kubectl create namespace cf
#kubectl create -n cf -f scf-kube-yml/cf/bosh
#kubectl create -n cf -f scf-kube-yml/cf/bosh-task/post-deployment-setup.yml
helm install scf-alpha/helm/cf \
     --namespace "cf" \
     --set "env.CLUSTER_ADMIN_PASSWORD=$CLUSTER_ADMIN_PASSWORD" \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "env.UAA_HOST=${UAA_HOST}" \
     --set "env.UAA_PORT=${UAA_PORT}" \
     --set "kube.external_ip=${K8S_HOST_IP}"
