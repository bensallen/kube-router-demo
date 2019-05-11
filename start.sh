#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

RANCHEROS_VERSION=${1:-v1.5.1}
NODE_COUNT=${2:-3}

if ! type jq > /dev/null 2>&1; then
    echo "Requires jq to be installed"
    exit 1
fi

if ! type docker-machine > /dev/null 2>&1; then
    echo "Requires docker-machine to be installed"
    exit 1
fi

CACHE_DIR=$(pwd)/cache

ISO_BASE_PATH=$CACHE_DIR/iso/$RANCHEROS_VERSION
ISO_PATH=$ISO_BASE_PATH/rancheros.iso
CHECKSUM_PATH=$ISO_BASE_PATH/iso-checksums.txt

[ -d $ISO_BASE_PATH ] || mkdir -p $ISO_BASE_PATH

echo -e "RancherOS Version: $RANCHEROS_VERSION"

if [ ! -f $ISO_PATH ]; then
    echo "\n* Downloading RancherOS $RANCHEROS_VERSION ..."
    wget https://github.com/rancher/os/releases/download/$RANCHEROS_VERSION/rancheros.iso -O $ISO_PATH >$ISO_BASE_PATH/wget.log 2>&1
fi

for i in $(seq 1 $NODE_COUNT); do
    if [ ! -e "$HOME/.docker/machine/machines/ros-vm${i}" ]; then
        docker-machine create -d virtualbox --virtualbox-boot2docker-url $ISO_PATH ros-vm${i}
    fi
    if [ $( docker-machine status ros-vm${i}) != "Running" ]; then
        docker-machine start ros-vm${i}
    fi
done

cat <<EOF > cluster.yml
---
nodes:
EOF

for i in $(seq 1 $NODE_COUNT); do
cat <<EOF >> cluster.yml
  - address: $(docker-machine inspect ros-vm$i | jq .Driver.IPAddress)
    hostname_override: ros-vm$i
    ssh_key_path: $(docker-machine inspect ros-vm$i | jq .Driver.SSHKeyPath)
    user: $(docker-machine inspect ros-vm$i | jq .Driver.SSHUser)
    role: [controlplane,worker,etcd]
EOF
done

cat <<EOF >> cluster.yml
services:
    kube-controller:
      cluster_cidr: 10.42.0.0/16
      service_cluster_ip_range: 10.43.0.0/16

network:
  plugin: none

ingress:
  provider: none
EOF

#rke up
#
for i in $(seq 1 $NODE_COUNT); do
    kubectl --kubeconfig=kube_config_cluster.yml annotate node ros-vm$i "kube-router.io/bgp-local-addresses=$(docker-machine inspect ros-vm$i | jq .Driver.IPAddress)"
done
#
kubectl --kubeconfig=kube_config_cluster.yml apply -f kube-router.yml