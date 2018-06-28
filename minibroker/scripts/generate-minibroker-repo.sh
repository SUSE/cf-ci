#!/usr/bin/env sh
set -e
set -x
cp s3.*chart/*.tgz repo
helm repo index --url https://minibroker-helm-charts.s3.amazonaws.com/minibroker-charts repo
