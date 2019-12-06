#!/usr/bin/env bash

gcloud auth revoke

gcloud auth activate-service-account --key-file=${SA_KEY_FILE}

gcloud config set project ${PROJECT}

gcloud container clusters get-credentials  ${CLUSTER_NAME} --zone ${CLUSTER_ZONE:?required}

checkready() {
    while [[ $node_readiness != "$NODE_COUNT True" ]]; do
        sleep 10
        node_readiness=$(
            kubectl get nodes -o json \
                | jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
                | uniq -c | grep -o '\S.*'
        )
    done
}

checkready
echo "Setting swap accounting"

# Set correct zone
gcloud config set compute/zone ${CLUSTER_ZONE:?required}

#Grab node instance names
set -- $(gcloud compute instances list --filter=name~${CLUSTER_NAME:?required} --format json | jq --raw-output '.[].name')

while [[ -n "${@}" ]]; do
    for node in ${@}; do
        # Update kernel command line, update GRUB and reboot
        gcloud compute ssh $node -- "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 net.ifnames=0\"/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 net.ifnames=0 cgroup_enable=memory swapaccount=1\"/g' /etc/default/grub.d/50-cloudimg-settings.cfg && sudo update-grub && sudo systemctl reboot -i"
    done
    checkready
    nodes_without_swap=()
    for node in ${@}; do
        if ! gcloud compute ssh $node -- 'sudo test -e "/sys/fs/cgroup/memory/memory.memsw.usage_in_bytes" && sudo test -e "/sys/fs/cgroup/memory/memory.memsw.limit_in_bytes" && echo SwapAccountingOK' | grep -q SwapAccountingOK; then
            nodes_without_swap+=($node)
        fi
    done
    set -- "${nodes_without_swap[@]}"
done
