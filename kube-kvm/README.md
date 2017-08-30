# Provisioning a Kubernetes host on KVM, without vagrant

# Table of Contents

  * [Overview](#overview)
    * [Why not always use Vagrant?](#why-not-always-use-vagrant)
  * [How to use this script](#how-to-use-this-script)
    * [Prerequisites](#prerequisites)
    * [Configuration](#configuration)
    * [Deployment](#deployment)
  * [How to use the VM](#how-to-use-the-vm)
    * [Installing Dev Tools](#installing-dev-tools)


# Overview

This script provides a general-purpose Kubernetes host, with kube-dns and helm deployed,
which is hospitable for SCF deployment

## Why Not Always Use Vagrant?

To be clear, the KVM image used by this deployment method is *packaged as a vagrant box* by
the packer vagrant post-provisioner. Even though the input is a vagrant box, using vagrant
to deploy it introduces a limitation of only being able to deploy one VM at a time on a
given KVM host. In order to fully utilize shared KVM hosts for development and testing, as
well as provide Kubernetes host pools for our CI systems, it is advantageous to have a way
to deploy a VM from the generated KVM image without using Vagrant.

It's important to be aware that the base image built by packer is intended to be a generic
kube host, and doesn't have direnv, fissile, or stampy. The script in scf
`bin/dev/install_tools.sh` can be run to install these tools, necessary for building
releases, images, and charts used for deploying SCF in development. SCF can also be
deployed from our chart bundle distributions, which use images on our docker hub.

# How to Use This Script

## Prerequisites

This script is intended to be run on a SLES box which has been installed as a KVM host. It
should also run on other KVM hosts which meet the following requirements, though limited
testing has been done:
- The `libvirt` user should be a member of the `root` group: `usermod -aG libvirt root`
- The default network defined in `net-default.xml` should be created and started:
  - `virsh net-define net-default.xml`
  - `virsh net-start default`
- A system time service (ntp or timedatectl) should be installed, synced, and started
- The KVM host machine should have internet access through a Linux host bridge device named
  `br0`. This is the default configuration when installing SLES as a KVM host. If using
  Wicked as your network manager, you can follow the instructions in step 4 of
  https://github.com/suse/scf#deploying to configure this bridge interface.

## Configuration

The `provision-kube-host-kvm.sh` script takes one argument, the name to use for the
deployed Kubernetes host VM. This may alternatively be configured by setting the
`KUBE_VM_NAME` environment variable.

#### WARNING:
_**If a VM with the name passed via the name argument already exists, it will be deleted!**_

Other variables which can be set to modify the behaviour of the deployment scripts are:

```
KUBE_VM_IMAGE_NAME # The name of the image in s3 to use. Defaults to the latest VM image
KUBE_VM_IMAGE_PATH # The path to use for storing images, VM disks, and the vm key
                   # This defaults to $HOME/qcow2-disks
KUBE_VM_MEM_GIB    # The memory to allocate to the VM. Defaults to 8GiB
```

## Deployment

To deploy a new VM, run `./provision-kube-host-kvm.sh <vm-name>`. See the above
[warning](#warning)

# How to Use the VM

Once the deployment of your VM is finished, the provisioning script will output information
about how to set your kubernetes config to access the VM, which will look like:

```
kubectl config set-cluster --server=${IP}:8080 my_vm
kubectl config set-context my_vm --cluster=my_vm
kubectl config use-context my_vm
```

You can also access the VM via ssh using the password `vagrant` for `vagrant@$IP`, or the
default vagrant VM access key which is downloaded as part of the provisioning to
`"${KUBE_VM_IMAGE_PATH}/vm-key"`

## Installing Dev Tools

When deploying a Kubernetes host with the provisioning script, direnv and the dev tools are
not installed. Should you wish to prepare the VM so that you can run `make vagrant-prep`,
you will need to run the following as the `vagrant` user:

```
mkdir -p /home/vagrant/bin
wget -O /home/vagrant/bin/direnv --no-verbose \
  https://github.com/direnv/direnv/releases/download/v2.11.3/direnv.linux-amd64
chmod a+x /home/vagrant/bin/direnv
echo 'eval "$(/home/vagrant/bin/direnv hook bash)"' >> ${HOME}/.bashrc
ln -s /home/vagrant/scf/bin/dev/vagrant-envrc ${HOME}/.envrc
/home/vagrant/bin/direnv allow ${HOME}
/home/vagrant/bin/direnv allow ${HOME}/scf
sudo -E SCF_BIN_DIR=/usr/local/bin HOME=/home/vagrant /home/vagrant/bin/direnv exec /home/vagrant/scf/bin/dev/install_tools.sh
```
