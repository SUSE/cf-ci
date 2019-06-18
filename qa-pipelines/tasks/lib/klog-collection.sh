#!/bin/bash

__generate_klog() {
  echo "Generating klog for namespace ${1}"
  klog.sh "${1}"
}

upload_klogs_on_failure() {
  # This function should run whenever the task exits with a failure.
  # Task scripts should unset this as the EXIT handler before successful exits
  local task_status=$?
  echo "Task exited with status ${task_status}"
  if [[ ${KLOG_COLLECTION_ON_FAILURE} != true ]]; then
    echo "klog-collection-on-failure flag unset. Skipping container log aggregation"
    return ${task_status}
  fi
  local klog_name=klog-$(date +%s)
  set +o errexit
  while [[ ${#} -gt 0 ]]; do
    __generate_klog "${1}" && klog_name="${klog_name}-${1}"
    shift
  done
  mkdir -p klog
  mv klog.tar.gz klog/${klog_name}.tar.gz
}
