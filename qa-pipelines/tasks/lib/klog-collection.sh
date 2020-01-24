#!/usr/bin/env bash

default_target_url="$(cat meta/atc-external-url)/builds/$(cat meta/build-id)"
echo "Setting default target_url for github notifications: ${default_target_url}"
mkdir -p klog
echo ${default_target_url} > klog/target_url

__generate_klog() {
  echo "Generating klog for namespace ${1}"
  klog.sh "${1}"
}

__set_errexit() {
  # Restores previous errexit status determined from shopt
  if [[ "${1:-}" == "on" ]]; then
    set -o errexit
  elif [[ "${1:-}" == "off" ]]; then
    set +o errexit
  fi
}

monitor_kubectl_pods()
(
  mkdir -p "$HOME/klog/monitor_kubectl_pods/"
  cd "$HOME/klog/monitor_kubectl_pods/"
  echo "monitoring kubectl pods"
  start_date=$(date +%s)
  while true; do
    time_since_start=$(($(date +%s) - ${start_date}))
    # zero-pad to 5 places for sorting when monitoring will last less than 27 hours
    time_since_start=$(printf "%05d\n" ${time_since_start})
    kubectl get pods --all-namespaces > new.log
    last_file=$(ls -tr1  | tail -2 | head -1)
    if [[ ${last_file} == new.log ]]; then
      mv new.log ${time_since_start}.log
    else
      if ! diff -q <(awk '{print $1, $2, $3, $4}' new.log) <(awk '{print $1, $2, $3, $4}' ${last_file})  > /dev/null; then
        mv new.log ${time_since_start}.log
      fi
    fi
    sleep 10
  done
)

upload_klogs_on_failure() {
  # This function should run whenever the task exits with a failure.
  # Task scripts should unset this as the EXIT handler before successful exits
  local task_status=$?
  echo "Task exited with status ${task_status}"
  if [[ "${KLOG_COLLECTION_ON_FAILURE:-false}" == false ]]; then
    echo "klog-collection-on-failure flag unset. Skipping container log aggregation"
    return ${task_status}
  fi
  local initial_errexit=$(shopt -o errexit | awk '{ print $2 }')
  set +o errexit
  local scf_version=$(cat commit-id/sha)
  local klog_name=klog-${scf_version}-$(date +%s)
  # Insert version file into ~/klog dir so it's included in the final klog tgz
  cp s3.scf-config/version klog
  cp -r meta ~/klog
  while [[ ${#} -gt 0 ]]; do
    __generate_klog "${1}" && klog_name="${klog_name}-${1}"
    shift
  done
  mkdir -p klog
  mv klog.tar.gz klog/${klog_name}.tar.gz
  local target_url="https://s3.amazonaws.com/${KLOG_COLLECTION_ON_FAILURE}/${klog_name}.tar.gz"
  echo "Overriding github notification target_url: ${target_url}"
  echo "${target_url}" > klog/target_url
  __set_errexit "${initial_errexit}"
}
