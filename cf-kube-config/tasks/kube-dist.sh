#!/bin/bash

set -ex

tar xf fissile-binary/fissile-* -C /usr/local/bin fissile
tar xf stampy-binary/stampy-* -C /usr/local/bin stampy

ci/cf-kube-config/tasks/common/start-docker.sh

cd src
source .envrc

make releases
make kube-dist

mv hcf-kube-*.zip ../out/
