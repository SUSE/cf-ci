#!/usr/bin/env bash

export MCRGNAME=$(az aks show --resource-group $RGNAME --name $AKSNAME --query nodeResourceGroup -o json | jq -r '.')

set -- $(az vm list --resource-group $MCRGNAME -o json | jq -r '.[] | select (.tags.poolName | contains("'$NODEPOOLNAME'")) | .name')

while [[ -n "${@}" ]]; do
    for node in ${@}; do
        az vm run-command invoke -g $MCRGNAME -n $node --command-id RunShellScript --scripts \
            "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 swapaccount=1\"|' \
            /etc/default/grub.d/50-cloudimg-settings.cfg && sudo update-grub"
        az vm restart -g $MCRGNAME -n $node
    done
    nodes_without_swap=()
    for node in ${@}; do
        if ! az vm run-command invoke -g $MCRGNAME -n $node --command-id RunShellScript --scripts 'test -e "/sys/fs/cgroup/memory/memory.memsw.usage_in_bytes" && test -e "/sys/fs/cgroup/memory/memory.memsw.limit_in_bytes" && echo SwapAccountingOK' | grep -q SwapAccountingOK; then
            nodes_without_swap+=($node)
        fi
    done
    set -- "${nodes_without_swap[@]}"
done
