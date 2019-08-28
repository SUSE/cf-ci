#!/usr/bin/env bash

export CF_CI_DIR=${CF_CI_DIR:-"$(git rev-parse --show-toplevel)"}

export CAASP_VER=${CAASP_VER:-"product"}
export STACK=${STACK:-"$(whoami)-${CAASP_VER::3}-caasp4-cf-ci"}
export WORKSPACE=${WORKSPACE:-"$(pwd)/workspace-$STACK"}
export DEBUG=${DEBUG:-0}
export KUBECTL_VER="v1.15.2" # TODO not used yet
export HELM_VER="v2.8.2" # TODO not used yet
export KUBECONFIG="$WORKSPACE"/kubeconfig
export MAGIC_DNS_SERVICE='omg.howdoi.website'

# prerrequisites:
if [[ "$(docker images -q skuba/$CAASP_VER 2> /dev/null)" == "" ]]; then
    make -C "$CF_CI_DIR"/docker/skuba/ "$CAASP_VER"
fi
if [[ ! -v OS_PASSWORD ]]; then
    echo ">>> Missing openstack credentials" && exit 1
fi

# k8s deploy:
"$CF_CI_DIR"/qa-tools/deploy-caasp4-os.sh

# k8s prepare:
"$CF_CI_DIR"/qa-tools/prepare-caasp.sh

# TODO cap deploy:
# "$CF_CI_DIR"/qa-pipelines/tasks/cf-deploy.sh

# TODO cap test:
# "$CF_CI_DIR"/qa-pipelines/tasks/run-test.sh

# play:
# cd "$WORKSPACE" && direnv allow
# kubectl get pods --all-namespaces
# helm ls

# TODO cap teardown:
# "$CF_CI_DIR"/qa-tools/cap-teardown.sh

# k8s destroy:
# cd "$WORKSPACE"/deployment
# "$CF_CI_DIR"/qa-tools/destroy-caasp4-os.sh
