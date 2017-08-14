#!/bin/bash

set -o nounset
set -o errexit

# EV 'PIPELINE_PREFIX' = prefix to pipeline name for local customization of test
#           pipelines

pipeline_name=cf-kube-dist

target="${1:-}"

if test -n "${CONCOURSE_SECRETS_FILE:-}"; then
    if test -r "${CONCOURSE_SECRETS_FILE:-}" ; then
        secrets_file="${CONCOURSE_SECRETS_FILE}"
    else
        printf "ERROR: Secrets file %s is not readable\n" "${CONCOURSE_SECRETS_FILE}" >&2
        exit 2
    fi
else
    echo "ERROR: CONCOURSE_SECRETS_FILE location is not set" >&2
    exit 3
fi

fly \
    ${target:+"--target=${target}"} \
    set-pipeline \
    -p "${PIPELINE_PREFIX:-}${pipeline_name}" \
    -c "${pipeline_name}/${pipeline_name}.yml" \
    -v s3-bucket=cf-opensusefs2 \
    -l <(gpg -d --no-tty "${secrets_file}" 2> /dev/null)

fly \
    ${target:+"--target=${target}"} \
    expose-pipeline \
    -p "${PIPELINE_PREFIX:-}${pipeline_name}"
fly \
    ${target:+"--target=${target}"} \
    unpause-pipeline \
    -p "${PIPELINE_PREFIX:-}${pipeline_name}"
