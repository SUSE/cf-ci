#!/bin/sh

set -o errexit -o nounset -o xtrace

GOPATH=$PWD/go
GOOS="${GOOS:-$(go env GOOS)}"
GOARCH="${GOARCH:-$(go env GOARCH)}"

export GOPATH GOOS GOARCH

package="github.com/square/certstrap"
version="$(git -C "${GOPATH}/src/${package}" describe --always)"


go build '-ldflags=-w' "${package}"
tar czf "out/certstrap-${version}.${GOOS}-${GOARCH}.tgz" \
    --numeric-owner \
    --owner=0 --group=0 \
    --checkpoint=.10 \
    certstrap
