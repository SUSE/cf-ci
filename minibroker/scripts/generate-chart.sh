#!/usr/bin/env sh
set -e
set -x
VERSION=$(awk '/^version:/{print $2}' "src/stable/${CHART_NAME}/Chart.yaml")-pr$(cat src/.git/id)
helm package --version "${VERSION}" --save=false --destination chart/ "src/stable/${CHART_NAME}"
