#!/usr/bin/env sh
set -e
set -x

# Prepare minibroker dir for building docker image
cp -R src minibroker/

# Build the executable
mkdir -p gopath/src/github.com/osbkit
cp -R src gopath/src/github.com/osbkit/minibroker
GOPATH=$PWD/gopath make -C gopath/src/github.com/osbkit/minibroker build-linux
cp gopath/src/github.com/osbkit/minibroker/minibroker-linux minibroker/src/image/minibroker
