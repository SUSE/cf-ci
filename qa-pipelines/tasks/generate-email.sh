#!/usr/bin/env bash
set -o errexit
set -o nounset

mkdir -p email
echo "Failure in concourse job $(cat meta/build-pipeline-name)/$(cat meta/build-job-name) build $(cat meta/build-name)" | tee -a  email/subject

echo "Status set at https://github.com/SUSE/scf/commits/$(cat commit-id/sha)" | tee -a email/body
echo "URL to build is $(cat meta/atc-external-url)/builds/$(cat meta/build-id)" | tee -a email/body
if [ -f klog/klog-* ]; then
  echo "For more information, view klog at $(cat klog/target_url)" >> email/body | tee -a email/body
fi
