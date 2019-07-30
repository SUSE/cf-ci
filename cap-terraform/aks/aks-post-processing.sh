#!/usr/bin/env bash

export MCRGNAME=$(az aks show --resource-group $RGNAME --name $AKSNAME --query nodeResourceGroup -o json | jq -r '.')

export VMNODES=$(az vm list --resource-group $MCRGNAME -o json | jq -r '.[] | select (.tags.poolName | contains("'$NODEPOOLNAME'")) | .name')

for i in $VMNODES
 do
   az vm run-command invoke -g $MCRGNAME -n $i --command-id RunShellScript --scripts \
   "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 swapaccount=1\"|' \
   /etc/default/grub.d/50-cloudimg-settings.cfg && sudo update-grub"
   az vm restart -g $MCRGNAME -n $i
done
