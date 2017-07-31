#!/usr/bin/env bash

# This script will connect to the kubernetes host assuming the expected
# environment variables are available

set -o errexit -o nounset

# Configure kubectl
kubectl config set-cluster --server="http://${K8S_HOST_IP}:${K8S_HOST_PORT}" "${K8S_HOSTNAME}"
kubectl config set-context "${K8S_HOSTNAME}" --cluster="${K8S_HOSTNAME}"
kubectl config use-context "${K8S_HOSTNAME}"
