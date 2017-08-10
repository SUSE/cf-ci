#!/bin/bash

target="$1"

# EV 'PIPELINE_PREFIX' = prefix to pipeline name for local
#                        customization of test pipelines

if test -n "${CONCOURSE_SECRETS_FILE:-}"; then
    if test -r "${CONCOURSE_SECRETS_FILE:-}" ; then
        secrets_file="${CONCOURSE_SECRETS_FILE}"
    else
        printf "ERROR: Secrets file %s is not readable\n" "${CONCOURSE_SECRETS_FILE}" >&2
        exit 2
    fi
fi

fly -t "$target" set-pipeline \
    -p ${PIPELINE_PREFIX}cf-ci-orchestration \
    -c cf-ci-orchestration/cf-ci-orchestration.yml \
    -v s3-bucket=cf-opensusefs2 \
    -l <(gpg -d --no-tty "${secrets_file}" 2> /dev/null)

fly -t "$target" expose-pipeline  -p ${PIPELINE_PREFIX}cf-ci-orchestration
fly -t "$target" unpause-pipeline -p ${PIPELINE_PREFIX}cf-ci-orchestration
