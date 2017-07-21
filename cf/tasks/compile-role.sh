#!/bin/bash

set -o errexit
set -o nounset
set -o xtrace

if test -z "${ROLE_NAME:-}" ; then
    echo "No role name specified" >&2
    exit 1
fi

tar -xf s3.fissile-binary/fissile-*.linux-amd64.tgz -C s3.fissile-binary fissile
export PATH=$PATH:$PWD/s3.fissile-binary

source "src/${PROJECT_DIR:-.}/.envrc"
export FISSILE_WORK_DIR="${PWD}/fissile-work-dir"
export FISSILE_CACHE_DIR="${PWD}/fissile-cache-dir"
mkdir -p "${FISSILE_CACHE_DIR}"

ci/cf/tasks/common/extract-all-releases.sh

fissile build packages --roles="${ROLE_NAME}" --without-docker
