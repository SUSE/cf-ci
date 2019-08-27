#!/usr/bin/env bash
set -euo pipefail

# Destroys an existing Caasp4 cluster on openstack
#
# Requirements:
# - Built skuba docker image
# - Sourced openrc.sh
# - Key on the ssh keyring

SKUBA_DEPLOY_PATH="$CF_CI_DIR"/qa-tools/skuba-deploy.sh
skuba-deploy() {
    bash "$SKUBA_DEPLOY_PATH" "$@"
}

export KUBECONFIG="$WORKSPACE"/kubeconfig

if [[ ! -v OS_PASSWORD ]]; then
    echo ">>> Missing openstack credentials" && exit 1
fi

if [[ -f "$KUBECONFIG" ]] &&  kubectl get storageclass 2>/dev/null | grep -qi persistent; then
    echo ">>> Destroying storageclass"
    # allows the nfs server to delete the share
    kubectl delete storageclass persistent
    wait
fi

echo ">>> Destroying deployed openstack stack"
cd "$WORKSPACE"/deployment
skuba-deploy --run-in-docker terraform destroy -auto-approve
echo ">>> Destroyed openstack stack"
