#!/bin/bash

set -ex


DIR_PATH=$(pwd)
#NOTES:
export HELM_VERSION="2.4.2"
bin_dir="${bin_dir:-/usr/local/bin/}"
helm_url="${helm_url:-https://kubernetes-helm.storage.googleapis.com/helm-v${HELM_VERSION}-linux-amd64.tar.gz}"
direnv_url="${direnv_url:-https://github.com/direnv/direnv/releases/download/v2.11.3/direnv.linux-amd64}"
#zypper --non-interactive addrepo http://download.opensuse.org/repositories/Virtualization:containers/openSUSE_Leap_42.2/Virtualization:containers.repo
#zypper  --non-interactive --gpg-auto-import-keys refresh
#mkdir -p "${bin_dir}"
#bin_dir="$(cd "${bin_dir}" && pwd)"
zypper --non-interactive install wget
zypper --non-interactive install tar
zypper --non-interactive install which

#install direnv
wget -O ${bin_dir}/direnv --no-verbose ${direnv_url}
chmod a+x ${bin_dir}/direnv

#install helm
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

unzip s3.scf-alpha/scf-linux-amd64-* -d scf-alpha
#unzip s3.scf-helm-charts/hcf-kube-charts-* -d scf-helm-charts
mkdir certs
cd scf-alpha
./cert-generator.sh -d ${DOMAIN} -n cf -o ../certs
cd $DIR_PATH
#Deploy UAA
kubectl create namespace uaa
#kubectl create -n uaa -f scf-kube-yml/uaa/bosh/
#kubectl create -n uaa -f scf-kube-yml/uaa/kube-test/exposed-ports.yml
helm install scf-alpha/helm/uaa \
     --set kube.storage_class.persistent=persistent \
     --namespace "uaa" \
     --values certs/uaa-cert-values.yaml \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "kube.external_ip=${K8S_HOST_IP}"


#Deploy CF
kubectl create namespace cf
#kubectl create -n cf -f scf-kube-yml/cf/bosh
#kubectl create -n cf -f scf-kube-yml/cf/bosh-task/post-deployment-setup.yml
helm install scf-alpha/helm/cf \
     --set kube.storage_class.persistent=persistent \
     --namespace "cf" \
     --values certs/scf-cert-values.yaml \
     --set "env.CLUSTER_ADMIN_PASSWORD=$CLUSTER_ADMIN_PASSWORD" \
     --set "env.DOMAIN=${DOMAIN}" \
     --set "env.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}" \
     --set "env.UAA_HOST=${UAA_HOST}" \
     --set "env.UAA_PORT=${UAA_PORT}" \
     --set "kube.external_ip=${K8S_HOST_IP}"

sleep 20m

kubectl get pods --all-namespaces
