#!/usr/bin/env bash

set -o errexit -o nounset

aws s3 cp sources/* s3://${BUCKET}/bosh-releases
