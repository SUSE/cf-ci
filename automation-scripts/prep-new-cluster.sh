#!/usr/bin/env bash

set -o errexit

kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: kube-system:default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: default
  namespace: kube-system
EOF
curl -sL "https://storage.googleapis.com/kubernetes-helm/helm-v2.13.1-linux-amd64.tar.gz" | tar xz -C /root/bin --strip-components=1 linux-amd64/helm
chmod +x /root/bin/helm
# Remove potential cache reference to lower-precedence helm executable
hash -d helm 2>/dev/null || true
echo "Installing helm client and tiller"
helm init --upgrade

if ! type k &>/dev/null ; then
  echo "Installing k"
  curl -sLo /root/bin/k "https://github.com/aarondl/kctl/releases/download/v0.0.12/kctl-linux-amd64"
  chmod +x /root/bin/k
fi


if ! type klog.sh &>/dev/null ; then
  echo "Installing klog"
  curl -sLo /root/bin/klog.sh "https://raw.githubusercontent.com/SUSE/scf/develop/container-host-files/opt/scf/bin/klog.sh"
  chmod +x /root/bin/klog.sh
fi

if ! type cf &>/dev/null; then
  echo "Installing cf and cf usb"
  curl -sL "https://packages.cloudfoundry.org/stable?release=linux64-binary&version=6.42.0&source=github-rel" | tar xz -C /root/bin cf
  chmod +x /root/bin/cf
  cf install-plugin -f "https://github.com/SUSE/cf-usb-plugin/releases/download/1.0.0/cf-usb-plugin-1.0.0.0.g47b49cd-linux-amd64 "
fi

if ! type jq &>/dev/null; then
  echo "Installing jq"
  curl -sLo /root/bin/jq "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64"
  chmod +x /root/bin/jq
fi

if ! kubectl get storageclass persistent &> /dev/null; then
  kubectl create -f "$(dirname $0)/nfs-provisioner"
fi

echo "Ensure the following config contents are in the lockfile for your concourse pool kube resource:"
echo "---"
curl -sL "https://raw.githubusercontent.com/SUSE/cf-ci/master/qa-tools/create-qa-config.sh" | bash 2>/dev/null | awk '/apiVersion/ { yaml=1 }  yaml { print }' | sed 's/:6444$/:6443/g'
