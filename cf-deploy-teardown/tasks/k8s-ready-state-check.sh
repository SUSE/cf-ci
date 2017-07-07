#!/bin/bash

#Script to determine is the K8s host is "ready" for cf deployment
FAILED=0

SCF_DOMAIN=${SCF_DOMAIN:-cf-dev.io}
function green() {
  awk '{ print "\033[32mVerified: " $0 "\033[0m" }';
}

function red() {
  awk '{ print "\033[31mConfiguration problem detected: " $0 "\033[0m" }';
}

function status() {
  if [ $? -eq 0 ]; then
    echo "$1" | green
  else
    echo "$1" | red
    FAILED=1
  fi
}
# cgroup memory & swap accounting in /proc/cmdline
grep -wq "cgroup_enable=memory" /proc/cmdline
status "cgroup_enable memory"

grep -wq "swapaccount=1" /proc/cmdline
status "swapaccount enable"

# docker info should show overlay2

docker info 2> /dev/null | grep -wq "Storage Driver: overlay2"
status "docker info should show overlay2"

# kube-dns shows 4/4 ready

kubectl get pods --namespace=kube-system --selector k8s-app=kube-dns | grep -Eq '([0-9])/\1 *Running'
status "kube-dns should shows 4/4 ready"

# ntp is installed and running

systemctl is-active ntpd >& /dev/null || systemctl is-active systemd-timesyncd >& /dev/null
status "ntp or systemd-timesyncd must be installed and active"

# "persistent" storage class exists in K8s

kubectl get storageclasses |& grep -wq "persistent"
status "'persistent' storage class should exist in K8s"

# privileged pods are enabled in K8s

kube_apiserver=$(systemctl status kube-apiserver -l | grep "/usr/bin/hyperkube apiserver" )
[[ $kube_apiserver == *"--allow-privileged"* ]]
status "Privileged must be enabled in 'kube-apiserver'"

kubelet=$(systemctl status kubelet -l | grep "/usr/bin/hyperkube kubelet" )
[[ $kubelet == *"--allow-privileged"* ]]
status "Privileged must be enabled in 'kubelet'"

# dns check for the current hostname resolution

IP=$(host -tA "${SCF_DOMAIN}" | awk '{ print $NF }')
/sbin/ifconfig | grep -wq "inet addr:$IP"
status "dns check"


# override tasks infinity in systemd configuration

systemctl cat containerd | grep -wq "TasksMax=infinity"
status "TasksMax must be set to infinity"

exit $FAILED
