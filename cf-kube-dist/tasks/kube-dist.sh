#!/bin/bash

set -ex

tar xf s3.fissile-binary/fissile-* -C /usr/local/bin fissile
tar xf s3.stampy-binary/stampy-* -C /usr/local/bin stampy

ci/cf-kube-dist/tasks/common/start-docker.sh

cd src
source .envrc

make releases
make kube-dist

mv hcf-kube-*.zip ../out/
