#!/usr/bin/env sh
set -e
set -x
helm package --save=false --destination chart/ "src/charts/minibroker"
