#!/usr/bin/env bash

#
set -euo pipefail

CLUSTER_NAME="iot"

echo "==> [1/6] Base packages"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates

echo "==> [2/6] Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER" || true
sudo systemctl enable --now docker || true


if ! docker info >/dev/null 2>&1; then
  echo
  echo "!! Docker installed but this shell can't use it yet."
  echo "!! Log out and back in (or run: newgrp docker), then re-run this script."
  exit 1
fi

echo "==> [3/6] kubectl"
if ! command -v kubectl >/dev/null 2>&1; then
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

echo "==> [4/6] k3d"
if ! command -v k3d >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo bash
fi

echo "==> [5/6] k3d cluster '${CLUSTER_NAME}'"
if ! k3d cluster list 2>/dev/null | grep -qw "${CLUSTER_NAME}"; then
  k3d cluster create "${CLUSTER_NAME}" --wait
fi
kubectl cluster-info

echo "==> [6/6] Namespaces + Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for Argo CD server to be ready (can take a few minutes)..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo
echo "=================================================="
echo " Argo CD ready."
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
echo "=================================================="
echo "Next step: ./deploy.sh"
