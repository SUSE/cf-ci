#!/bin/bash

archive="$(echo "fissile-output/fissile-${ROLE_NAME}:"*.tar)"
tar xf "${archive}" -C adjusted-role-image

image_tag="${archive#*:}"
image_tag="${image_tag%.*}"
echo "${image_tag}" > "adjusted-role-image/${ROLE_NAME}.tag"

base_id="$(cat docker-fissile-role-packages/image-id)"
perl -p -i -e "s@^FROM .*@FROM ${base_id}@" adjusted-role-image/Dockerfile

echo "${ROLE_NAME} image FROM adjusted to ${base_id}"
