#!/usr/bin/env bash

set -o errexit

if ! type helm &>/dev/null ; then
  curl -sL "https://storage.googleapis.com/kubernetes-helm/helm-v2.6.1-linux-amd64.tar.gz" | tar xz -C /root/bin --strip-components=1 linux-amd64/helm
  chmod +x /root/bin/helm
  if kubectl get pods --all-namespaces 2>/dev/null | grep -qi tiller; then
    helm init --client-only
  else
    helm init
    kubectl create -f - << EOF
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
  fi
fi

if ! type k &>/dev/null ; then
  curl -sLo /root/bin/k "https://github.com/aarondl/kctl/releases/download/v0.0.12/kctl-linux-amd64"
  chmod +x /root/bin/k
fi

 
if ! type klog.sh &>/dev/null ; then
  curl -sLo /root/bin/klog.sh "https://raw.githubusercontent.com/SUSE/scf/develop/container-host-files/opt/scf/bin/klog.sh"
  chmod +x /root/bin/klog.sh
fi

echo "Ensure the following config contents are in the lockfile for your concourse pool kube resource:"
echo "---"
curl -sL "https://raw.githubusercontent.com/SUSE/cf-ci/master/automation-scripts/create-qa-config.sh" | bash 2>/dev/null | awk '/apiVersion/ { yaml=1 }  yaml { print }'
