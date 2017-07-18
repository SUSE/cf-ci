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

tar -xf s3.certstrap-binary/certstrap-*.linux-amd64.tgz -C s3.certstrap-binary certstrap
export PATH=$PATH:$PWD/s3.certstrap-binary

source src/.envrc
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
    # Build UAA bits
    cd src
    source .envrc
    cd src/uaa-fissile-release
    source .envrc
    # XXX marky hack until uaa-fissile-release#35 lands
    perl -p -i -e 's@head -c 32 /dev/urandom \| xxd -ps -c 32@LC_CTYPE=C tr -cd 0-9a-f < /dev/urandom \| head -c64@' generate-certs.sh
    make certs kube helm
)
(
    # Workaround for dependencies on UAA that are silly
    cd src
    source .envrc
    bin/settings/kube/ca.sh
    head make/kube
    make/kube
    # XXX marky Helm is busted WRT to FISSILE_OUTPUT_DIR
    /usr/bin/env FISSILE_OUTPUT_DIR="${PWD}/helm" make/kube helm
    make/kube-dist
)

mv src/scf-kube-*.zip out/
