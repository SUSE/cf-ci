#!/bin/bash

set -o errexit
set -o nounset
set -o xtrace

tar -xf fissile-binary/fissile-*.linux-amd64.tgz -C fissile-binary fissile
export PATH="${PATH}:${PWD}/fissile-binary"

ci/cf/tasks/common/start-docker.sh

docker load --input ubuntu-base/image
fissile build layer stemcell --from="$(cat ubuntu-base/image-id)"

image_name="fissile-role-base"
image_tag="$(docker images '--format={{.Tag}}' "${image_name}")"
echo "${image_name}" > out/repository
echo "${image_tag}" > out/tag
docker inspect --format='{{.Id}}' "${image_name}:${image_tag}" > out/image-id
docker save --output out/image "${image_name}:${image_tag}"
