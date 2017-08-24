#!/usr/bin/env bash

# This script is intended to be run on a SLES box installed as a KVM host.
# After OS installation, the following commands should also be run to set up directory
# permissions and the default network (as root):
# - usermod -aG libvirt root
# - virsh net-define net-default.xml
# - virsh net-start default
# - ntpdate time.nist.gov
# - systemctl enable ntpd
# - systemctl start ntpd

set -o errexit

export KUBE_VM_NAME=${KUBE_VM_NAME:-$1}
export KUBE_VM_IMAGE_NAME=${KUBE_VM_IMAGE_NAME:-scf-libvirt-v2.0.6}
export KUBE_VM_IMAGE_PATH=${KUBE_VM_IMAGE_PATH:-~/qcow2-disks}
export KUBE_VM_MEM_GIB=${KUBE_VM_MEM_GIB:-8}

# Used for displaying external setup information at end of provisioning
export OBJECT_STORAGE_BASE_URL=${OBJECT_STORAGE_BASE_URL:-\${OBJECT_STORAGE_BASE_URL}}
export OBJECT_STORAGE_YAML_BUCKET=${OBJECT_STORAGE_YAML_BUCKET:-kube-config}

mkdir -p "$KUBE_VM_IMAGE_PATH"
cd "$KUBE_VM_IMAGE_PATH"

if [[ -z "$KUBE_VM_NAME" ]]; then
  echo "A VM name must be provided"
  exit 1
fi

# Fetch base image if it doesn't exist
if [[ ! -f $KUBE_VM_IMAGE_NAME.qcow2 ]]; then
  echo "Fetching base image:"
  curl -L https://cf-opensusefs2.s3.amazonaws.com/vagrant/${KUBE_VM_IMAGE_NAME}.box | tar --wildcards box.img -xz
  mv box.img $KUBE_VM_IMAGE_NAME.qcow2
fi

# Fetch VM access key if it doesn't exist
if [[ ! -f vm-key ]]; then
  curl -sL -o "vm-key" https://raw.githubusercontent.com/mitchellh/vagrant/v1.9.6/keys/vagrant
  chmod 400 vm-key
fi
KUBE_VM_KEY=${KUBE_VM_KEY:-$PWD/vm-key} 

if [[ $KUBE_VM_MEM_GIB -gt $(( $(free -g | grep [0-9] | head -1 | awk '{print $2}') - 2 )) ]]; then
  echo KUBE_VM_MEM_GIB value $KUBE_VM_MEM_GIB exceeds system resources
  exit 1
fi

unset RUNNING_VM_IMAGE
if virsh domstate $KUBE_VM_NAME 2>/dev/null; then
  echo "Deleting existing domain $KUBE_VM_NAME"
  RUNNING_VM_IMAGE=$(virsh dumpxml $KUBE_VM_NAME | grep 'source file' | grep -o "'.*'" | tr -d "'")
  if [[ -z $RUNNING_VM_IMAGE ]]; then
    echo "Disk for domain $KUBE_VM_NAME could not be determined. Please delete this domain manually"
    exit 1
  fi
  virsh destroy "$KUBE_VM_NAME"
  virsh undefine "$KUBE_VM_NAME"
  rm -f "$RUNNING_VM_IMAGE"
fi

cp "$KUBE_VM_IMAGE_NAME.qcow2" "$KUBE_VM_IMAGE_NAME-$KUBE_VM_NAME.qcow2"
# TODO: Test if virbr0 is present
virt-install \
  --name "$KUBE_VM_NAME" \
  --memory $(( KUBE_VM_MEM_GIB * 1024 )) \
  --vcpus 1 \
  --disk "$KUBE_VM_IMAGE_NAME-$KUBE_VM_NAME.qcow2" \
  --import \
  --network network=default \
  --network bridge=br0 \
  --os-variant opensuse42.2 \
  --wait 0 \
  --hvm

echo "Sleeping 30 seconds to allow VM to start and obtain IP"
sleep 30 
unset KUBE_VM_DEFAULT_IP
# TODO: Clean up variable assignment (timeouts)
IP_WAIT_TIMEOUT=150
KUBE_VM_DEFAULT_MAC=$(virsh domiflist "$KUBE_VM_NAME" | grep default | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}') || true
if [[ -z "$KUBE_VM_DEFAULT_MAC" ]]; then
  echo "No MAC address for default interface on VM $KUBE_VM_NAME. Check output of \`sudo virsh domiflist $KUBE_VM_NAME\`"
  exit 1
fi
while [[ -z "$KUBE_VM_DEFAULT_IP" ]]; do
  echo "Checking if IP lease exists for interface $KUBE_VM_DEFAULT_MAC"
  KUBE_VM_DEFAULT_IP=$(virsh net-dhcp-leases default --mac "$KUBE_VM_DEFAULT_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}') || true
  if [[ -z "$KUBE_VM_DEFAULT_IP" ]]; then
    if [[ "$IP_WAIT_TIMEOUT" -ge 0 ]]; then
      (( IP_WAIT_TIMEOUT -= 15 ))
      echo "No IP assigned for $KUBE_VM_DEFAULT_MAC. Retrying in 15 seconds"
      sleep 15
    else
      echo "No IP assigned for $KUBE_VM_DEFAULT_MAC after 3 minutes. Exiting."
      exit 1
    fi
  fi
done
echo "Docker VM IP found: $KUBE_VM_DEFAULT_IP. Waiting for sshd to start"
SSHD_TIMEOUT=60
while [[ $SSHD_TIMEOUT -ge 0 ]]; do
  nc $KUBE_VM_DEFAULT_IP 22 </dev/null | grep 'SSH-' && break
  sleep 5
  (( SSHD_TIMEOUT -= 5 ))
done
ssh-keygen -R $KUBE_VM_DEFAULT_IP
ssh -o StrictHostKeyChecking=no -Ti "$KUBE_VM_KEY" vagrant@$KUBE_VM_DEFAULT_IP -- sudo bash -o errexit << EOF
hostname $KUBE_VM_NAME
echo $KUBE_VM_NAME > /etc/hostname
cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth1
echo DHCLIENT_SET_DEFAULT_ROUTE='yes' /etc/sysconfig/network/ifcfg-eth1
wicked ifup eth1
EOF

KUBE_VM_BRIDGED_IP=$(ssh -i "$KUBE_VM_KEY" vagrant@$KUBE_VM_DEFAULT_IP 'ip -4 addr show eth1' | tr / ' ' | awk '/inet/ { print $2 }')
if [[ -z "$KUBE_VM_BRIDGED_IP" ]]; then
  echo "There was a problem getting the IP of the bridged interface. See output of \`ifconfig eth1\` in VM $KUBE_VM_NAME"
  exit 1
fi

ssh-keygen -R $KUBE_VM_BRIDGED_IP
ssh -o StrictHostKeyChecking=no -Ti "$KUBE_VM_KEY" vagrant@$KUBE_VM_BRIDGED_IP  << EOF
git clone https://github.com/suse/scf
cd scf
sudo bash -o errexit << EOSU
export SCF_BIN_DIR=/usr/local/bin
./bin/common/install_tools.sh
EOSU
EOF

cat << EOF
Kube deployment completed successfully!

-----------------------------------------------------------------------------------------------------------------------------------------------------
# Run the following commands in an environment with kubectl to target this kube cluster:
kubectl config set-cluster --server=$KUBE_VM_BRIDGED_IP:8080 $KUBE_VM_NAME
kubectl config set-context $KUBE_VM_NAME --cluster=$KUBE_VM_NAME
kubectl config use-context $KUBE_VM_NAME
EOF
