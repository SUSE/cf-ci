#!/bin/bash

set -o errexit
set -o nounset

out="${PWD}/out/version"

cd src
make/print-version > "${out}"
