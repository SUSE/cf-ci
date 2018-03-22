#!/usr/bin/env sh
set -e
GOPATH=$PWD
make -C src/github.com/SUSE/cf-usb-plugin tools
