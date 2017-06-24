#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

set -x

export IMAGE_ROOT="$PWD/image-root"

mkdir -p /sys/fs/cgroup
mountpoint -q /sys/fs/cgroup || \
  mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

sed -e '1d;s/\([^\t]\)\t.*$/\1/' < /proc/cgroups | while IFS= read -r d; do
  mkdir -p "/sys/fs/cgroup/$d"
  mountpoint -q "/sys/fs/cgroup/$d" || \
    mount -n -t cgroup -o "$d" "$d" "/sys/fs/cgroup/$d" || \
    :
done

# We currently assume we can put the graph in /tmp/build/graph; in our
# configuration, that's btrfs and the subvolumes will get cleaned up correctly
# the concourse removes the volume.
mkdir -p /tmp/build/graph
# We need to pipe stdout + stderr to cat so that dockerd exits correctly when we're done
( dockerd --data-root /tmp/build/graph --mtu 1432 &> >(cat) ) &

until docker info >/dev/null 2>&1; do
  echo waiting for docker to come up...
  sleep 1
done
