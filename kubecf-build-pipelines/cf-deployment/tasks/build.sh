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
stemcell_image="${STEMCELL_REPOSITORY}:${STEMCELL_VERSION}"
docker pull "${stemcell_image}"

# Build the releases.
tasks_dir="$(dirname $0)"
bash <(yq -r ".manifest_version as \$cf_version | .releases[] | select(.name != \"pxc\") | \"source ${tasks_dir}/build_release.sh; build_release \\(\$cf_version|@sh) '${REGISTRY_NAME}' '${REGISTRY_ORG}' '${stemcell_image}' \\(.name|@sh) \\(.url|@sh) \\(.version|@sh) \\(.sha1|@sh)\"" "${CF_DEPLOYMENT_YAML}")
