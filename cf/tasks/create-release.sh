#!/bin/bash

set -o errexit
set -o nounset
set -o xtrace

mkdir bosh-cache

RELEASE_DIR=${RELEASE_DIR}
RELEASE_NAME=${RELEASE_NAME:-$(basename "${RELEASE_DIR}" -release)}
if test -r "${RELEASE_DIR}/.ruby-version" ; then
    RUBY_VERSION=$(cat "${RELEASE_DIR}/.ruby-version")
    export RUBY_VERSION
fi

/usr/local/bin/create-release.sh \
    "$(id -u)" "$(id -g)" \
    "${PWD}/bosh-cache" \
    --dir "${RELEASE_DIR}" \
    --force \
    --name "${RELEASE_NAME}"

# Get the release name, version, and commit for the file name.
# The commit needs to be there for concourse to distinguish between builds.
# It's not used for anything else and should not be exposed outside CI.
release_info=$(awk '/latest_release_filename:/ { print $2 }' < "${RELEASE_DIR}/config/dev.yml" | tr -d '"')
function field() {
    awk "/^${1}:/ { print \$2 }" < "${release_info}"
}
tar_name="${RELEASE_NAME}-release-tarball-$(field version)-$(field commit_hash).tgz"

mkdir stage
mv "${PWD}/bosh-cache"             stage/bosh-cache
mv "${RELEASE_DIR}/.dev_builds"    stage/dev-builds
mv "${RELEASE_DIR}/config/dev.yml" stage/dev.yml
mv "${RELEASE_DIR}/dev_releases"   stage/dev-releases
tar -czf "out/${tar_name}" --checkpoint=.1000 -C stage .
