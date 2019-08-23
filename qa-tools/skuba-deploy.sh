#!/usr/bin/env bash
set -euo pipefail

if [[ ! -v DEBUG ]]; then
    export DEBUG=0
fi
CLUSTER_NAME="my-cluster"

USAGE=$(cat <<USAGE
Usage:

--deploy

--updates <target> <action>
    --updates all disable

--reboots <target> <action>
    --reboots all disable

--node-upgrade <target>
    --node-upgrade all
    --node-upgrade masters
    --node-upgrade workers

--show-images

--run-cmd <target> "sudo ..."

--run-in-docker <docker_binary>

--scp <target> <src_files> <dest_files>
USAGE
)

skuba_container() {
  local app_path="$PWD"
  if [[ "$1" == "$CLUSTER_NAME" ]]; then
      local app_path="$PWD/$1"
      shift
  fi

  docker run -i --rm \
  -v "$app_path":/app:rw \
  -v "$(dirname "$SSH_AUTH_SOCK")":"$(dirname "$SSH_AUTH_SOCK")" \
  -v "/etc/passwd:/etc/passwd:ro" \
  --env-file <( env| cut -f1 -d= ) \
  -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
  -u "$(id -u)":"$(id -g)" \
  skuba/$CAASP_VER "$@"
}

ssh2() {
  local host=$1
  shift
  ssh -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -F /dev/null \
      -o LogLevel=ERROR \
      "sles@$host" "$@"
}

wait_ssh() {
    timeout=$2
    define_node_group "$1"
    for n in $GROUP; do
        secs=0
        set +e
        ssh2 $n exit
        while test $? -gt 0
        do
            if [ $secs -gt $timeout ] ; then
                echo ">>> Timeout while waiting for $n"
                exit 2
            else
                sleep 5
                secs=$(( secs + 5 ))
                ssh2 $n exit
            fi
        done
        set -e
    done
}

reboots() {
#kubectl -n kube-system patch ds kured -p '{"spec":{"template":{"metadata":{"labels":{"name":"kured"}},"spec":{"containers":[{"name":"kured","command":["/usr/bin/kured", "--period=10s"]}]}}}}'
  local action="$1"
  if [[ "$action" == "disable" ]]; then
    kubectl -n kube-system annotate ds kured weave.works/kured-node-lock='{"nodeID":"manual"}'
  else
    kubectl -n kube-system annotate ds kured weave.works/kured-node-lock-
  fi
}

run_cmd() {
  define_node_group "$1"
  CMD="$2"
  for n in $GROUP; do
      echo ">>> Running '$CMD' on $n"
      ssh2 "$n" "$CMD"
  done
}

use_scp() {
  define_node_group "$1"
  SRC="$2"
  DEST="$3"
  local options="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -F /dev/null -o LogLevel=ERROR -r"

  for n in $GROUP; do
      echo ">>> SCP '$SRC' to '$DEST' on $n"
      scp "$options" "$SRC" sles@$n:"$DEST"
  done
}

show_images() {
  kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" | tr -s '[[:space:]]' '\n'
}

updates() {
  define_node_group "$1"
  local action="$2"
  for n in $GROUP; do
      echo ">>> $action skuba-update on $n"
      ssh2 "$n" "sudo systemctl $action --now skuba-update.timer"
  done
}

init_control_plane() {
  if ! [[ -d "$CLUSTER_NAME" ]]; then
      echo ">>> Deploying control plane"
      skuba_container skuba cluster init --control-plane "$LB" "$CLUSTER_NAME"
  fi
}

deploy_masters() {
local i=0
for n in $1; do
    local j="$(printf "%03g" $i)"
    if [[ $i -eq 0 ]]; then
      echo ">>> Boostrapping first master node, master$j: $n"
      skuba_container "$CLUSTER_NAME" skuba node bootstrap --user sles --sudo --target "$n" "master$j" -v "$DEBUG"
      wait
    fi

    if [[ $i -ne 0 ]]; then
      echo ">>> Boostrapping other master nodes, master$j: $n"
      skuba_container "$CLUSTER_NAME" skuba node join --role master --user sles --sudo --target  "$n" "master$j" -v "$DEBUG"
      wait
    fi
    ((++i))
done
}

deploy_workers() {
  local i=0
  for n in $1; do
      local j="$(printf "%03g" $i)"
      echo ">>> Deploying workers, worker$j: $n"
      (skuba_container "$CLUSTER_NAME" skuba node join --role worker --user sles --sudo --target  "$n" "worker$j" -v "$DEBUG") &
      wait
      ((++i))
  done
}

deploy() {
  init_control_plane
  pushd $(pwd)/
  deploy_masters "$MASTERS"
  deploy_workers "$WORKERS"
  echo ">>> Cluster bootstraped:"
  skuba_container $CLUSTER_NAME skuba cluster status
}

set_env_vars() {
    JSON=$(skuba_container terraform output -json)
    export LB=$(echo "$JSON" | jq -r '.ip_load_balancer.value')
    export MASTERS=$(echo "$JSON" | jq -r '.ip_masters.value[]')
    export WORKERS=$(echo "$JSON" | jq -r '.ip_workers.value[]')
    export ALL="$MASTERS $WORKERS"
}

define_node_group() {
  set_env_vars
  case "$1" in
    "all")
    GROUP="$ALL"
    ;;
    "masters")
    GROUP="$MASTERS"
    ;;
    "workers")
    GROUP="$WORKERS"
    ;;
    *)
    GROUP="$1"
    ;;
  esac
}

node_upgrade() {
  define_node_group "$1"

  local i=0
  for n in $GROUP; do
  #    local j="$(printf "%03g" $i)"
      echo ">>> Upgrading node $n"

  #    skuba "$CLUSTER_NAME" node upgrade plan  -v "$DEBUG"
      skuba_container "$CLUSTER_NAME" skuba node upgrade apply --user sles --sudo --target "$n" -v "$DEBUG"
  #  ((++i))
  done
}

# Parse options
while [[ $# -gt 0 ]] ; do
    case $1 in
    --deploy)
      set_env_vars
      deploy
      ;;
    --run-in-docker)
      shift
      skuba_container "$@"
      ;;
    --node-upgrade)
      node_upgrade "$TARGET"
      ;;
    --updates)
      TARGET="${2:-all}"
      ACTION="${3:-disable}"
      updates "$TARGET" "$ACTION"
      ;;
    --reboots)
      ACTION="${2:-disable}"
      reboots "$ACTION"
      ;;
    --run-cmd)
      TARGET="${2:-all}"
      CMD="$3"
      run_cmd "$TARGET" "$CMD"
      ;;
    --wait-ssh)
      TARGET="${2:-all}"
      TIMEOUT="${3:-30}"
      wait_ssh "$TARGET" "$TIMEOUT"
      ;;
    --scp)
      TARGET="${2:-all}"
      SRC="$3"
      DEST="$4"
      use_scp "$TARGET" "$SRC" "$DEST"
      ;;
    --show-images)
      show_images
      ;;
    -h|--help)
      echo "$USAGE"
      exit 0
      ;;
    esac
    shift
done
