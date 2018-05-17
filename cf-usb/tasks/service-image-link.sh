#! /usr/bin/env bash

# This script just displays the link necessary to copy the docker images to the
# production registry

# The helm chart bundle URL, URL escaped.
export BUNDLE_URL="$(perl -lpe 's/(\W)/sprintf("%%%02X", ord($1))/ge' < bundle/url)"
echo "${RELEASE_TOOL_URL}?release_archive_url=${BUNDLE_URL}"
