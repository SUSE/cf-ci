#!/usr/bin/env bash
set -euo pipefail

# Destroys an existing Caasp4 cluster on openstack
#
# Expected env var           Eg:
#   VERSION                  devel, staging, product, update. default: devel
#
# Requirements:
# - Built skuba docker image
# - Sourced openrc.sh
# - Key on the ssh keyring
# - Run inside of a workspace of a deployed caasp4 in openstack

if [[ ! -v VERSION ]]; then
    export VERSION="devel"
fi

export SKUBA_TAG="$VERSION"
SKUBA_DEPLOY_PATH=$(dirname "$(readlink -f "$0")")/skuba-deploy.sh
skuba-deploy() {
    bash "$SKUBA_DEPLOY_PATH" "$@"
}

export KUBECONFIG=""

if [[ ! -v OS_PASSWORD ]]; then
    echo ">>> Missing openstack credentials" && exit 1
fi


echo ">>> Destroying deployed openstack stack"
skuba-deploy --run-in-docker terraform destroy -auto-approve
echo ">>> Destroyed openstack stack"
