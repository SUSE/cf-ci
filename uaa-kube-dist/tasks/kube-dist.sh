#!/bin/bash

set -ex

export PATH=$PATH:/opt/rubies/ruby-2.3.1/bin

gem install bosh_cli --no-ri --no-rdoc

# Need xxd for the cert stuff
apt-get update && apt-get install -qy vim-common

tar xf s3.fissile-binary/fissile-* -C /usr/local/bin fissile
tar xf s3.stampy-binary/stampy-* -C /usr/local/bin stampy

ci/uaa-kube-dist/tasks/common/start-docker.sh

cd src
source .envrc

make certs releases kube kube-dist

mv uaa-kube-*.zip ../out/
