#!/usr/bin/env bash

set -o errexit -o nounset

# Start the Docker daemon.
source build-image-resource/assets/common.sh
max_concurrent_downloads=10
max_concurrent_uploads=10
insecure_registries=""
registry_mirror=""
start_docker \
  "${max_concurrent_downloads}" \
  "${max_concurrent_uploads}" \
  "${insecure_registries}" \
  "${registry_mirror}"
trap 'stop_docker' EXIT

# Login to the Docker registry.
echo "${REGISTRY_PASS}" | docker login "${REGISTRY_NAME}" --username "${REGISTRY_USER}" --password-stdin

# Extract the fissile binary.
tar xvf s3.fissile-linux/fissile-*.tgz --directory "/usr/local/bin/"

# Pull the stemcell image.
stemcell_version="$(cat s3.stemcell-version/"${STEMCELL_VERSIONED_FILE##*/}")"
stemcell_image="${STEMCELL_REPOSITORY}:${stemcell_version}"
docker pull "${stemcell_image}"

# Build the releases.
tasks_dir="$(dirname $0)"
base_dir=$(pwd)

RELEASE_URL+=$([[ ${RELEASE_URL} == *"bosh.io"* ]] && echo ?v=$RELEASE_VERSION || echo -${RELEASE_VERSION}.tgz)
curl -sL ${RELEASE_URL} --output ${base_dir}/${RELEASE_NAME}-${RELEASE_VERSION}.tgz
RELEASE_SHA=$(sha1sum ${base_dir}/${RELEASE_NAME}-${RELEASE_VERSION}.tgz | cut -d' ' -f1)

# Build the releases.
tasks_dir="$(dirname $0)"
bash <(.releases[] | \"source ${tasks_dir}/build_release.sh; build_release \\(\$cf_version|@sh) '${REGISTRY_NAME}' '${REGISTRY_ORG}' '${stemcell_image}' \\(.name|@sh) \\(.url|@sh) \\(.version|@sh) \\(.sha1|@sh)\"" "${EXTERNAL_RELEASES_YAML}")
