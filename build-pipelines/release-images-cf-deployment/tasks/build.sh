#!/usr/bin/env bash

set -o errexit -o nounset

# Start the Docker daemon.
source docker-image-resource/assets/common.sh
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
echo "${DOCKER_TEAM_PASSWORD_RW}" | docker login "${DOCKER_REGISTRY}" --username "${DOCKER_TEAM_USERNAME}" --password-stdin

# Extract the fissile binary.
tar xvf s3.fissile-linux/fissile-*.tgz --directory "/usr/local/bin/"

# Rename the bosh binary.
mv bosh-cli/${BOSH_CLI_GLOB} "/usr/local/bin/bosh"

# Pull the stemcell image.
stemcell_version="$(cat s3.stemcell-version/"${STEMCELL_VERSIONED_FILE##*/}")"
stemcell_image="${STEMCELL_REPOSITORY}:${stemcell_version}"
docker pull "${stemcell_image}"

# Apply buildpacks ops-file.
cf_deployment_yaml_with_suse_buildpacks="$(mktemp -dt XXXXXX)"
bosh interpolate "${CF_DEPLOYMENT_YAML}" --ops-file "${SCF_OPS_SET_SUSE_BUILDPACKS}" > "${cf_deployment_yaml_with_suse_buildpacks}"

# Build the releases.
tasks_dir="$(dirname $0)"
bash <(yq -r ".manifest_version as \$cf_version | .releases[] | \"source ${tasks_dir}/build_release.sh; build_release \\(\$cf_version|@sh) '${DOCKER_REGISTRY}' '${DOCKER_ORGANIZATION}' '${DOCKER_TEAM_USERNAME}' '${DOCKER_TEAM_PASSWORD_RW}' '${STEMCELL_OS}' '${stemcell_version}' '${stemcell_image}' \\(.name|@sh) \\(.url|@sh) \\(.version|@sh) \\(.sha1|@sh)\"" "${cf_deployment_yaml_with_suse_buildpacks}")
