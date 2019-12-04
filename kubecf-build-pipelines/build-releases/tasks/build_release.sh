#!/bin/bash

set -e

mkdir /bosh-cache

ROOT_DIR=$PWD

# Some repositories host the bosh release in a subdirectory
if [ -n "${RELEASE_DIRECTORY}" ]; then
  pushd $RELEASE_DIRECTORY
fi

cat > config/private.yml <<EOF
---
blobstore:
  options:
    access_key_id: "$ACCESS_KEY_ID"
    secret_access_key: "$SECRET_ACCESS_KEY"
EOF

VERSION=$(git describe --tags --abbrev=0)
RELEASE_TARBALL_BASE_NAME=${RELEASE_NAME}-release-${VERSION}.tgz
RELEASE_TARBALL=$ROOT_DIR/release_tarball_dir/${RELEASE_TARBALL_BASE_NAME}

/usr/local/bin/bosh.sh \
    "$(id -u)" "$(id -g)" /bosh-cache create-release \
    --final \
    --version=${VERSION} \
    --tarball=${RELEASE_TARBALL}
