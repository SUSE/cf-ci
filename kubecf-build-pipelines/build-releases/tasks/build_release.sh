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

# Extract Major, Minor and Patch-Level version based on a regex (only for releases
# who are versioned based on blobs.yml files).
# For the rest, the next patchlevel is returned.
if [ -n "${VERSION_REGEXP}" ]; then
  VERSION=$(head -n2 config/blobs.yml | tail -n1 | perl -pe "s/$VERSION_REGEXP/\1/p")

  echo "Will now generate version ${VERSION} (\$VERSION_REGEXP was used)"
else
  OLD_VERSION=$(git describe --tags --abbrev=0)
  # Increase patch level by one (TODO: Find simpler way)
  VERSION="$(echo $OLD_VERSION | sed -e 's/\(.*\)\.[0-9]\+/\1/').$(($(echo $OLD_VERSION | rev | cut -d. -f1 | rev)+1))"

  echo "Old version is ${OLD_VERSION}"
  echo "Will now generate version ${VERSION}"
fi

RELEASE_TARBALL_BASE_NAME=${RELEASE_NAME}-release-${VERSION}.tgz
RELEASE_TARBALL=$ROOT_DIR/release_tarball_dir/${RELEASE_TARBALL_BASE_NAME}

/usr/local/bin/bosh.sh \
    "$(id -u)" "$(id -g)" /bosh-cache create-release \
    --final \
    --version=${VERSION} \
    --tarball=${RELEASE_TARBALL}
