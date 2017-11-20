#!/bin/sh
set -o errexit -o nounset

export SIDECAR_ROOT="${PWD}/src/github.com/SUSE/cf-usb-sidecar"
export GOPATH="${PWD}"
export GOBIN="${PWD}/out/SIDECAR_BIN"
cp -r generated "${SIDECAR_ROOT}/"

mkdir -p out/docs/
cp -r "${SIDECAR_ROOT}/docs/package-files" out/docs/
cp "${SIDECAR_ROOT}/scripts/docker/release/Dockerfile-release" out/Dockerfile

cd "${SIDECAR_ROOT}"
if ! test -d vendor ; then
    # Symlinks don't work here because go(.exe) expands the symlink then falls over
    cp -r Godeps/_workspace/src vendor
    cp -r go-swagger/src/* vendor/
fi
mkdir -p "${GOBIN}"
go install ./cmd/catalog-service-manager
