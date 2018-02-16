#!/bin/sh
set -o nounset -o errexit -o xtrace
export GOPATH="${PWD}"
export START_DIR="${PWD}"
usbroot=src/github.com/SUSE/cf-usb-sidecar
svcroot="${usbroot}/csm-extensions/services/dev-${SERVICE}"

make -C "${svcroot}" build helm

# Default destination, and strip a trailing slash.
DESTINATION=${DESTINATION:-docker.io}
DESTINATION=${DESTINATION%/}

# Place chosen destination into the chart.
sed -i "s|docker.io|$DESTINATION|" "${svcroot}/output/helm/values.yaml"

# Note that this moves the whole SIDECAR_HOME directory as a _subdirectory_ of out/
mv "${svcroot}/SIDECAR_HOME"     docker-out/
cp "${svcroot}/Dockerfile"       docker-out/
cp "${svcroot}/Dockerfile-setup" docker-out/
cp "${svcroot}/Dockerfile-db"    docker-out/
cp -r "${svcroot}/chart"         docker-out/

if test -z "${APP_VERSION_TAG:-}" ; then
    APP_VERSION_TAG="$(cd "${usbroot}" && scripts/build_version.sh "APP_VERSION_TAG")"
fi
echo "${APP_VERSION_TAG}" > docker-out/tag
tar -czf helm-out/cf-usb-sidecar-${SERVICE}-${APP_VERSION_TAG}.tgz -C "${svcroot}/output/helm/" .
