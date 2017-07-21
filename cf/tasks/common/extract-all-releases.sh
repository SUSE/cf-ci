#!/bin/bash

# This file extracts the contents of s3.all-releases-tarball into src/
# It assumes we're starting from the task directory

set -o errexit
set -o nounset

# Instead of extracting the tar file and moving the results to the correct
# places, we instead iterate through the release names and determine the
# sed(1)-style transform required to make tar(1) do it for us.  While this
# results in a few unreadable expressions here, it reduces disk usage somewhat
# (which is especially an issue on concourse vagrant boxes).
ARTIFACT_DIR="${ARTIFACT_DIR:-${PWD}/s3.all-releases-tarball}"
tar_filename="$(echo "${ARTIFACT_DIR}/${FISSILE_REPOSITORY}-all-releases-"*.tgz)"
tar_command=( tar xvf "${tar_filename}" --show-transformed-names )

releases_var="${FISSILE_REPOSITORY^^}_RELEASES"
for release in ${!releases_var} ; do
    release_dir_var="$(echo "${FISSILE_REPOSITORY^^}_${release^^}_PATH" | tr - _)"
    release_dir="src/${!release_dir_var}"

    mkdir -p "${release_dir}/.dev_builds/"
    tar_command+=(
        --transform="s@^./${FISSILE_REPOSITORY}-${release}/bosh-cache@${FISSILE_CACHE_DIR#${PWD}/}@"
        --transform="s@^./${FISSILE_REPOSITORY}-${release}/dev-builds@${release_dir}/.dev_builds@"
        --transform="s@^./${FISSILE_REPOSITORY}-${release}/dev\\.yml@${release_dir}/config/dev.yml@"
        --transform="s@^./${FISSILE_REPOSITORY}-${release}/dev-releases@${release_dir}/dev_releases@"
    )
done

"${tar_command[@]}"

# The toplevel release directory themselves are empty; we transformed all of
# their contents to the correct places already.  Clean them up so when we
# hijack the containers they aren't there to disctract us.
rmdir ./*-release || true
