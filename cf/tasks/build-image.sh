#!/bin/bash

set -o errexit
set -o nounset

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

base_id="$(cat docker.fissile-stemcell/image-id)"

mkdir -p "out/${FISSILE_DOCKER_ORGANIZATION}"
fissile build images --roles="${ROLE_NAME}" --force --output-directory "${PWD}/out" --stemcell-id "${base_id}"

mkdir "out/role-packages"
archive="$(echo "out/${FISSILE_REPOSITORY:-fissile}-role-packages"*.tar)"
tar xf "${archive}" -C "out/role-packages"
image_tag="${archive#*:}"
image_tag="${image_tag%.*}"
echo "${image_tag}" > "out/role-packages.tag"

# Fix up the FROM line because concourse insists on using the wrong repo/tag
perl -p -i -e "s@^FROM .*@FROM ${base_id}@" out/role-packages/Dockerfile
