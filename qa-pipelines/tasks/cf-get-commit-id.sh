#!/usr/bin/env bash

# inputs:
#   s3.archive: the archive to examine
# outputs:
#   commit-id/sha: commit id to use (may be shortened)

if [[ -n ${CAP_BUNDLE_URL} ]]; then
    echo ${CAP_BUNDLE_URL} | sed 's/.*scf-sle-\(.*\).zip/\1/g' > version
    VERSION_FILE=version
else
    VERSION_FILE=s3.archive/version
fi
cat "${VERSION_FILE}" \
    | awk -F. '{print $NF}' \
    | tr -d g \
    | tee /dev/stderr \
    > commit-id/sha
