#!/bin/bash

set -o errexit
set -o nounset

if test -z "${ROLE_NAME:-}" ; then
    echo "No role name specified" >&2
    exit 1
fi

tar -xf fissile-binary/fissile-*.linux-amd64.tgz -C fissile-binary fissile
export PATH=$PATH:$PWD/fissile-binary

source src/.envrc
export FISSILE_WORK_DIR="${PWD}/fissile-work-dir"
mkdir -p "${FISSILE_CACHE_DIR}"

# Instead of extracting the tar file and moving the results to the correct
# places, we instead iterate through the release names and determine the
# sed(1)-style transform required to make tar(1) do it for us.  While this
# results in a few unreadable expressions here, it reduces disk usage somewhat
# (which is especially an issue on concourse vagrant boxes).
tar_filename="$(echo "${PWD}"/all-releases-tarball/all-releases-*.tgz)"
tar_command=( tar xvf "${tar_filename}" --show-transformed-names )

for release in ${RELEASES} ; do
    release_dir_var="$(echo "${release^^}_PATH" | tr - _)"
    release_dir="src/${!release_dir_var}"

    mkdir -p "${release_dir}/.dev_builds/"
    tar_command+=(
        --transform="s@^./${release}/bosh-cache@${FISSILE_CACHE_DIR#${PWD}/}@"
        --transform="s@^./${release}/dev-builds@${release_dir}/.dev_builds@"
        --transform="s@^./${release}/dev\\.yml@${release_dir}/config/dev.yml@"
        --transform="s@^./${release}/dev-releases@${release_dir}/dev_releases@"
    )
done

"${tar_command[@]}"

# The toplevel release directory themselves are empty; we transformed all of
# their contents to the correct places already.  Clean them up so when we
# hijack the containers they aren't there to disctract us.
rmdir ./*-release || true

fissile build packages --roles="${ROLE_NAME}" --without-docker
