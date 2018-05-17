#!/bin/sh
set -o errexit
set -o xtrace
set -o nounset

status_name="$1"
state="$2"
description="$3"

cd src
sha=$(git rev-parse HEAD)
repo_name=$(git remote get-url origin | sed -e 's#^\(.*[@/]\)\{0,1\}github.com[:/]##' -e 's#.git$##')

if test -z "$description" ; then
  create_status "$repo_name" "$sha" "$state" --context "$status_name"
else
  create_status "$repo_name" "$sha" "$state" --context "$status_name" --description "$description"
fi
