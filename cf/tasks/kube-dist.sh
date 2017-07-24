#!/bin/bash

set -o errexit
set -o nounset
set -o xtrace

# Work around concourse-filter being clbuttic
rm -f /etc/profile.d/filter.sh
exec 1> /proc/$(pidof concourse-filter)/fd/1
exec 2> /proc/$(pidof concourse-filter)/fd/2

tar -xf s3.fissile-binary/fissile-*.linux-amd64.tgz -C s3.fissile-binary fissile
export PATH=$PATH:$PWD/s3.fissile-binary

tar -xf s3.stampy-binary/stampy-*.linux-amd64.tgz -C s3.stampy-binary stampy
export PATH=$PATH:$PWD/s3.stampy-binary

tar -xf s3.certstrap-binary.linux/certstrap-*.linux-amd64.tgz \
    -C s3.certstrap-binary.linux \
    certstrap
export PATH=$PATH:$PWD/s3.certstrap-binary.linux

pushd src
source .envrc
popd
export FISSILE_WORK_DIR="${PWD}/fissile-work-dir"
mkdir -p "${FISSILE_CACHE_DIR}"

#ci/cf/tasks/common/start-docker.sh
(
    export FISSILE_REPOSITORY="scf"
    export ARTIFACT_DIR="${PWD}/s3.scf-all-releases-tarball"
    ci/cf/tasks/common/extract-all-releases.sh
)
(
    export FISSILE_REPOSITORY="uaa"
    export ARTIFACT_DIR="${PWD}/s3.uaa-all-releases-tarball"
    ci/cf/tasks/common/extract-all-releases.sh
)

(
    export FISSILE_BINARY="$PWD/s3.fissile-binary/fissile"
    touch "${FISSILE_BINARY}" # ensure we don't try to install tools
    timeout 5m make -C src uaa-certs kube helm kube-dist
)

mv src/scf-{kube,helm}-*.zip out/
