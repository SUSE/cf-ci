#!/usr/bin/env bash

set -o errexit -o nounset

# Start Docker Daemon (and set a trap to stop it once this script is done)
echo 'DOCKER_OPTS="--data-root /scratch/docker --max-concurrent-downloads 10"' >/etc/default/docker
systemctl docker start
systemctl docker status
trap 'systemctl docker stop' EXIT
sleep 10

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
bash <(yq -r ".releases[] | \"source ${tasks_dir}/build_release.sh; build_release '${REGISTRY_NAME}' '${REGISTRY_ORG}' '${stemcell_image}' \\(.name|@sh) \\(.url|@sh) \\(.version|@sh) \\(.sha1|@sh)\"" "${base_dir}/external-releases/${EXTERNAL_RELEASES_YAML}")
