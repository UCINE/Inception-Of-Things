#!/bin/bash
set -e

NODE_IP="192.168.56.110"

echo "Installing k3s server..."

curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip="${NODE_IP}" \
  --advertise-address="${NODE_IP}" \
  --bind-address="${NODE_IP}" \
    --write-kubeconfig-mode=644 \
  --flannel-iface="eth1"


echo "Master node setup complete."

while [ ! -s /var/lib/rancher/k3s/server/node-token ]; do
  sleep 2
done

kubectl apply -f /vagrant/app1.yaml
kubectl apply -f /vagrant/app2.yaml
kubectl apply -f /vagrant/app3.yaml
kubectl apply -f /vagrant/ingress.yaml
