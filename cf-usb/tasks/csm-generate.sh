#!/bin/sh
set -o errexit -o nounset -o xtrace
export ROOT="${PWD}"
export SIDECAR_ROOT="${ROOT}/src/github.com/SUSE/cf-usb-sidecar"
export GOBIN="${ROOT}/out/"
export GOPATH="${ROOT}"
cd "${SIDECAR_ROOT}"
cp -r go-swagger/src/* vendor/

"${SIDECAR_ROOT}/scripts/generate-server.sh"
"${SIDECAR_ROOT}/scripts/generate-csm-client.sh"

mv "${SIDECAR_ROOT}/generated/"* "${ROOT}/generated/"
