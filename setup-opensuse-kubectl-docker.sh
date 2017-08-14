#!/bin/bash

set -o nounset
set -o errexit

# EV 'PIPELINE_PREFIX' = prefix to pipeline name for local customization of test
#           pipelines

PIPELINE_NAME=cf-ci-orchestration

if test -z "${1:-}"; then
    printf "Usage:\n%s <target>\n" "${0}" >&2
    exit 1
fi

target="${1}"

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

fly -t "${target}" set-pipeline \
    -p "${PIPELINE_PREFIX}${PIPELINE_NAME}" \
    -c "${PIPELINE_NAME}/${PIPELINE_NAME}.yml" \
    -v s3-bucket=cf-opensusefs2 \
    -l <(gpg -d --no-tty "${secrets_file}" 2> /dev/null)

fly -t "${target}" expose-pipeline  -p "${PIPELINE_PREFIX}${PIPELINE_NAME}"
fly -t "${target}" unpause-pipeline -p "${PIPELINE_PREFIX}${PIPELINE_NAME}"
