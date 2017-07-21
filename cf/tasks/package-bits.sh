#!/bin/bash

set -x
set -o errexit
set -o nounset

#find . -print

# Determine configuration.
VERSION=$(cat semver.scf-version/version)

# Provide the certstrap binaries to SCF, for its cert-generator (CG).
# We rename them a bit (strip version) into the form expected by CG.
for OS in linux darwin
do
    cp s3.certstrap-binary.${OS}/certstrap-*.${OS}-amd64.tgz \
	src/certstrap-${OS}-amd64.tgz
done
# Create the directory the cert-gen assumes to exist
mkdir src/output
( cd src ; make cert-generator )

# We now have `src/output/scf-cert-generator.*-amd64.tgz`

for OS in linux darwin
do
    ARCHIVE="${PWD}/out/scf-${OS}-amd64-${VERSION}.zip"

    echo Packaging for $OS, taking $VERSION ...

    # Assembling the pieces ...
    mkdir tmp

    # kube configs
    # helm charts
    unzip s3.kube-dist/scf-kube-*.zip -d tmp

    # "Am I Ok" for k8s
    cp src/bin/dev/k8s-ready-state-check.sh tmp

    # cert scripts, and
    # certstrap
    tar -xzf src/output/scf-cert-generator.${OS}-amd64.tgz -C tmp

    # Package the assembly. This directly places it into the output
    ( cd tmp ; zip -r9 $ARCHIVE * )

    rm -rf tmp
done
