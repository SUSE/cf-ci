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

if [ "$(uname)" == "Darwin" ]; then
	args=I
else
	args=i
fi
echo "Setting swap accounting"

#Grab node instance names
instance_names=$(gcloud compute instances list --filter=name~${CLUSTER_NAME:?required} --format json | jq --raw-output '.[].name')

# Set correct zone
gcloud config set compute/zone ${CLUSTER_ZONE:?required}

# Update kernel command line, update GRUB and reboot
echo "$instance_names" | xargs -${args}{} gcloud compute ssh {} -- "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 net.ifnames=0\"/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 net.ifnames=0 cgroup_enable=memory swapaccount=1\"/g' /etc/default/grub.d/50-cloudimg-settings.cfg && sudo update-grub && sudo systemctl reboot -i"

echo "restarted the VMs"
checkready
