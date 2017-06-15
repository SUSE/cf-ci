#Script to determine is the K8s host is "ready" for cf deployment

set -ex

# cgroup memory & swap accounting in /proc/cmdline

cat /proc/cmdline | grep -w "cgroup_enable=memory"
echo "Verified: cgroug_enable memory"

cat /proc/cmdline | grep -w "swapaccount=1"
echo "Verified: swapaccount enabled"

# docker info should show overlay2

docker info | grep -w "Storage Driver: overlay2"
echo "Verified: 'docker info should show overlay2'"

# kube-dns shows 4/4 ready

kube_dns=$(k get pods : | grep "kube-dns-")
if [[ $kube_dns == *"4/4 Running"* ]]; then
  echo "Verified: 'kube-dns shows 4/4 ready'"
fi

# ntp is installed and running

systemctl status ntpd| grep -w "Active: active (running)"
echo "Verified: ntp is running"

# "persistent" storage class exists in K8s

k get storageclasses | grep -w "persistent   StorageClass.v1.storage.k8s.io"
echo "Verified: 'persistent' storage class exists in K8s"

# privileged pods are enabled in K8s

kube_apiserver=$(systemctl status kube-apiserver -l | grep "/usr/bin/hyperkube apiserver" )
if [[ $kube_apiserver == *"--allow-privileged"* ]]; then
  echo "Verified: privileged enabled in 'kube-apiserver'"
fi

kube_apiserver=$(systemctl status kubelet -l | grep "/usr/bin/hyperkube kubelet" )
if [[ $kube_apiserver == *"--allow-privileged"* ]]; then
  echo "Verified: privileged enabled in 'kubelet'"
fi

# dns check for the current hostname resolution

IP=$(nslookup cf-dev.io | grep answer: -A 2 | grep Address: | sed 's/Address: *//g')
#TODO: replace cf-dev.io with $hostaname.ci.van when this script is implimented in CI
sudo ifconfig | grep -w "inet addr:$IP"
echo "Verified: dns check"

# override tasks infinity in systemd configuration

systemctl cat containerd | grep -w "TasksMax=infinity"
echo "Verified: TasksMax set to infinity"

