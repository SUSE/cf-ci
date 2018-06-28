#!/bin/bash
# Deploys CAP 1.1.1 on caasp2 on engcloud and run smoke tests
# usage: PRIVATE_IP=172.28.0.11 EXTERNAL_IP=10.86.0.156 DOCKER_INTERNAL_REGISTRY= DOCKER_INTERNAL_USERNAME= DOCKER_INTERNAL_PASSWORD= bash cap-deploy-on-engcloud.sh
set -o errexit -o nounset
set -x

# Set variables
MAGIC_DNS_SERVICE=omg.howdoi.website
KUBE_REGISTRY_HOSTNAME=${DOCKER_INTERNAL_REGISTRY}
KUBE_REGISTRY_USERNAME=${DOCKER_INTERNAL_USERNAME}
KUBE_REGISTRY_PASSWORD=${DOCKER_INTERNAL_PASSWORD}
KUBE_ORGANIZATION=splatform
HA=false
SCALED_HA=true
CAP_INSTALL_VERSION=https://s3.amazonaws.com/cap-release-archives/master/scf-sle-2.10.1%2Bcf1.15.0.0.g647b2273.zip

CAP_CHART=""
#CAP_CHART="-opensuse"

source "../qa-pipelines/tasks/cf-deploy.sh"

# Run Smoke tests
ENABLE_CF_SMOKE_TESTS=true
source "../qa-pipelines/tasks/run-test.sh"

