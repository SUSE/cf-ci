#!/bin/bash

set -ex

export PATH=$PATH:/opt/rubies/ruby-2.3.1/bin

gem install bosh_cli --no-ri --no-rdoc

tar xf s3.fissile-binary/fissile-* -C /usr/local/bin fissile

cd src
source .envrc

make releases kube-configs package-kube

mv uaa-kube-*.zip ../out/
