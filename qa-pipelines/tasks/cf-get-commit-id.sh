#!/usr/bin/env bash

# inputs:
#   s3.archive: the archive to examine
# outputs:
#   commit-id/sha: commit id to use (may be shortened)

cat s3.archive/version \
    | awk -F. '{print $NF}' \
    | tr -d g \
    | tee /dev/stderr \
    > commit-id/sha
