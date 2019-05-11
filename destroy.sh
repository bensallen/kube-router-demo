#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

NODE_COUNT=${1:-3}

for i in $(seq 1 $NODE_COUNT); do
    if [ -e "$HOME/.docker/machine/machines/ros-vm${i}" ]; then
        docker-machine rm -f ros-vm${i}
    fi
done
