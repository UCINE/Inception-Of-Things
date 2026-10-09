#!/bin/bash
set -euo pipefail

NODE_IP="192.168.56.110"

# apk add --no-cache curl sudo iproute2

echo "Installing k3s server..."
curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip="${NODE_IP}" \
  --advertise-address="${NODE_IP}" \
  --bind-address="${NODE_IP}" \
  --write-kubeconfig-mode=644 \
  --disable=traefik \
  --disable=metrics-server \
  --disable-helm-controller \
  --disable=servicelb \
  --flannel-iface="eth1"

echo "Waiting for token file..."
while [ ! -s /var/lib/rancher/k3s/server/node-token ]; do
  sleep 2
done

TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token | tr -d '\n')

echo "$TOKEN" | sudo tee /vagrant/token > /dev/null

# echo "Making eth1 (${NODE_IP}) the primary/default interface..."
# ip route del default 2>/dev/null || true
# ip route add default via 192.168.56.1 dev "eth1"
echo "Master node setup complete."