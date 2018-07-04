#!/usr/bin/env sh
set -e
set -x
cp s3.*chart/*.tgz repo
helm repo index --url "https://${MINIBROKER_BUCKET}.s3.amazonaws.com/${CHARTS_DIR}" repo
