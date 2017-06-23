#!/bin/bash

set -ex

export PATH=$PATH:$HOME/bin

# Need xxd for the UAA cert code
apt-get update && apt-get install -qy vim-common

tar xf s3.fissile-binary/fissile-* -C /usr/local/bin fissile
tar xf s3.stampy-binary/stampy-* -C /usr/local/bin stampy

ci/cf-kube-dist/tasks/common/start-docker.sh

cd src
source .envrc

make releases uaa-certs uaa-releases kube-dist

mv hcf-kube-*.zip ../out/
