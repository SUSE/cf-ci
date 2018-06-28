#!/usr/bin/env sh
set -e
set -x

# Prepare minibroker dir for building docker image
cp -R src minibroker/

# Build the executable
mkdir -p gopath/src/github.com/osbkit
cp -R src gopath/src/github.com/osbkit/minibroker
export GOPATH=$PWD/gopath
cd gopath/src/github.com/osbkit/minibroker
make build-linux
cd -
cp gopath/src/github.com/osbkit/minibroker/minibroker-linux minibroker/src/image/minibroker
