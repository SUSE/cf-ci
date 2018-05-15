#!/usr/bin/env sh
set -e
PATH=$PATH:$PWD/bin
GOPATH=$PWD
make -C src/github.com/SUSE/cf-usb-plugin test
