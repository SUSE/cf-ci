#!/bin/sh

set -o errexit -o nounset -o xtrace

export GOPATH=$PWD/go

package="github.com/square/certstrap"
go build "${package}"
version="$(git -C "${GOPATH}/src/${package}" describe --always)"
tar czf "out/certstrap-${version}.tgz" \
    --numeric-owner \
    --owner=0 --group=0 \
    --checkpoint=.10 \
    certstrap
