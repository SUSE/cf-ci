#!/bin/bash
set -ex

#export k8s-host details from pool
set -a; source pool.k8s-hosts/metadata; set +a

#target the kube cluster
ssh-keygen -N "" -f /root/.ssh/id_rsa
sshpass -e ssh-copy-id -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_HOST_IP}
kubectl config set-cluster --server=${K8S_HOST_IP}:${K8S_HOST_PORT} ${K8S_HOSTNAME}
kubectl config set-context ${K8S_HOSTNAME} --cluster=${K8S_HOSTNAME}
kubectl config use-context ${K8S_HOSTNAME}

unzip s3.scf-config.linux/scf-linux-amd64-* -d scf-config

image=$(awk '/image/ { print $2 }' < scf-config/kube/cf/bosh-task/acceptance-tests-brain.yml)
sed -i "s/cf-dev\.io/${DOMAIN}/g" scf-alpha/kube/cf/bosh-task/acceptance-tests.yml
jsonify() { ruby -r yaml -r json -e 'YAML.load_stream(File.read "'"$1"'").each { |yaml| puts yaml.to_json}'; }
kubectl run -n cf --attach --restart=Never --image ${image} --overrides="$(jsonify scf-config/kube/cf/bosh-task/acceptance-tests-brain.yml)" acceptance-tests-brain
