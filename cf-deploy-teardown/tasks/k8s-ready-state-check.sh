#!/bin/bash

#Script to determine is the K8s host is "ready" for cf deployment

function green() {
  awk '{ print "\033[32mVerified: " $0 "\033[0m" }';
}

function red() {
  awk '{ print "\033[31mConfiguration problem detected: " $0 "\033[0m" }';
}

# cgroup memory & swap accounting in /proc/cmdline

echo "cgroup_enable memory" | ( grep -wq "cgroup_enable=memory" /proc/cmdline && green || red )



echo "swapaccount enable" | ( grep -wq "swapaccount=1" /proc/cmdline && green || red )

# docker info should show overlay2

echo "docker info should show overlay2" | ( docker info | grep -wq "Storage Driver: overlay2" && green || red )

# kube-dns shows 4/4 ready

echo "kube-dns should shows 4/4 ready" | (
    kube_dns=$(kubectl get pods --all-namespaces | grep -q "kube-dns-")
    [[ $kube_dns == *"4/4 Running"* ]] && green || red
)

# ntp is installed and running


echo "ntp must be installed and active" | ( systemctl is-active ntpd >& /dev/null && green || red )

# "persistent" storage class exists in K8s

echo "'persistent' storage class should exist in K8s" | (
    kubectl get storageclasses |& grep -wq "persistent   StorageClass.v1.storage.k8s.io" && green || red
)


# privileged pods are enabled in K8s

echo "Privileged must be enabled in 'kube-apiserver'" | (
    kube_apiserver=$(systemctl status kube-apiserver -l | grep "/usr/bin/hyperkube apiserver" )
    [[ $kube_apiserver == *"--allow-privileged"* ]] && green || red
)

echo "Privileged must be enabled in 'kubelet'" | (
    kubelet=$(systemctl status kubelet -l | grep "/usr/bin/hyperkube kubelet" )
    [[ $kubelet == *"--allow-privileged"* ]] && green || red
)

# dns check for the current hostname resolution

echo "dns check" | (
    IP=$(nslookup cf-dev.io | grep answer: -A 2 | grep Address: | sed 's/Address: *//g')
    #TODO: replace cf-dev.io with $hostname.ci.van when this script is implemented in CI
    /sbin/ifconfig | grep -wq "inet addr:$IP" && green || red
)


# override tasks infinity in systemd configuration

echo "TasksMax must be set to infinity" | (
    systemctl cat containerd | grep -wq "TasksMax=infinity" && green || red
)
