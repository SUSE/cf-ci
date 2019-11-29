#!/usr/bin/env bash

set -o errexit -o nounset

# Start Docker Daemon (and set a trap to stop it once this script is done)
echo 'DOCKER_OPTS="--data-root /scratch/docker --max-concurrent-downloads 10"' >/etc/default/docker
service docker start
service docker status
trap 'service docker stop' EXIT
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
base_dir=$(pwd)
# Get version from the GitHub release that triggered this task
pushd gh_release
RELEASE_VERSION=$(cat version)
RELEASE_URL=$(cat body | grep -o "Release Tarball: .*" | sed 's/Release Tarball: //')
RELEASE_SHA=$(sha1sum ${base_dir}/s3.*/*.tgz | cut -d' ' -f1)
popd

tasks_dir="$(dirname $0)"
source ${tasks_dir}/build_release.sh
build_release "${REGISTRY_NAME}" "${REGISTRY_ORG}" "${stemcell_image}" "${RELEASE_NAME}" "${RELEASE_URL}" "${RELEASE_VERSION}" "${RELEASE_SHA}"
