#!/usr/bin/env bash

# This script publishes the cf-usb-sidecar bundle
# Most arguments come from the task definition

set -o errexit

# Need to set up access to the appropriate repos
eval "$(ssh-agent)"
trap "ssh-agent -k" EXIT

grep --null-data '^GITHUB_KEY=' /proc/self/environ \
    | tail -c +12 \
    | tr '\0' '\n' \
    | ssh-add /dev/stdin
unset GITHUB_KEY

# Pick up the SSH host key
ssh -o StrictHostKeyChecking=no -l git github.com <&- 2>&1 \
    | grep "successfully authenticated"

export SIDECAR_BUNDLE="$(cat bundle/url)"
exec src/scripts/create_helm_charts_pr.sh
