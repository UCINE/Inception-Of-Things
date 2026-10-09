#!/bin/bash
set -euo pipefail

WORKER_IP="192.168.56.111"
MASTER_IP="192.168.56.110"

# apk add --no-cache curl iproute2

echo "Waiting for token file..."
while [ ! -f /vagrant/token ]; do
  sleep 2
done

TOKEN=$(cat /vagrant/token | tr -d '\n')


echo "Installing k3s agent..."
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="${TOKEN}" sh -s - agent \
  --node-ip="${WORKER_IP}" \
  --bind-address="${WORKER_IP}" \
  --flannel-iface="eth1"

# echo "Making eth1 (${WORKER_IP}) the primary interface..."
# ip route del default 2>/dev/null || true
# ip route add default via 192.168.56.1 dev "eth1"

echo "Worker node setup complete."