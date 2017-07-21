#!/bin/bash

set -x
set -o errexit
set -o nounset

#find . -print

# Determine configuration.

VERSION=$(cat semver.scf-version/version)
PLATFORM=$(echo $(basename s3.certstrap-binary/certstrap-*.tgz .tgz)|sed -e 's|\(.*\)\.\([^.]*\)$|\2|')
ARCHIVE="${PWD}/out/scf-${PLATFORM}-${VERSION}.zip"

echo Packaging for $PLATFORM, taking $VERSION ...

# Assembling the pieces ...
mkdir tmp

# kube configs
# helm charts
unzip ../s3.kube-dist/scf-kube-*.zip -d tmp

# "Am I Ok" for k8s
cp src/bin/dev/k8s-ready-state-check.sh tmp/

# NOTE: Code below is a variant of `src/make/cert-generator`, modified
# to take the certstrap binary from the task's input instead of
# directly from AWS S3, etc. Further modified to not generate a
# tarball, but leave things in the area of assembly.

# certstrap binary
mkdir -p tmp/scripts
cat s3.certstrap-binary/certstrap-*.tgz | tar -xzC "tmp/scripts/" certstrap

# certgen scripts
sed "s#@@CERTSTRAP_OS@@#${PLATFORM}#" \
    "src/bin/cert-generator-wrapper.sh.in" \
    > "tmp/cert-generator.sh"
chmod a+x "tmp/cert-generator.sh"
cp "src/bin/generate-dev-certs.sh" "tmp/scripts/generate-scf-certs.sh"
cp "src/src/uaa-fissile-release/generate-certs.sh" "tmp/scripts/generate-uaa-certs.sh"

# Package the assembly. This directly places it into the output
( cd tmp ; zip -r9 $ARCHIVE * )
