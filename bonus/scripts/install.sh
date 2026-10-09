#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="iot"
CLUSTER_CONTEXT="k3d-${CLUSTER_NAME}"
CLUSTER_API_PORT="${CLUSTER_API_PORT:-6550}"
RESET_CLUSTER="${RESET_CLUSTER:-0}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.4}"
ARGOCD_IMAGE="quay.io/argoproj/argocd:${ARGOCD_VERSION}"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run this script with sudo."
  echo "Run it as your normal user: ./scripts/install.sh"
  exit 1
fi

ensure_namespace() {
  local namespace="$1"
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
}

wait_for_argocd() {
  if kubectl wait --for=condition=available --timeout=1800s deployment/argocd-server -n argocd; then
    return
  fi

  echo
  echo "Argo CD did not become ready. Current pod status:"
  kubectl get pods -n argocd -o wide || true

  echo
  echo "Recent Argo CD events:"
  kubectl get events -n argocd --sort-by=.lastTimestamp | tail -30 || true

  echo
  echo "If pods show ImagePullBackOff or ContainerCreating for a long time,"
  echo "the cluster is still downloading the Argo CD image from quay.io."
  exit 1
}

preload_coredns_image() {
  local image
  local runtime_image
  local first_part

  echo "==> Preloading CoreDNS image"
  image="$(kubectl -n kube-system get deployment coredns -o jsonpath='{.spec.template.spec.containers[0].image}')"
  runtime_image="${image}"
  first_part="${runtime_image%%/*}"

  if [[ "${first_part}" != *.* && "${first_part}" != *:* && "${first_part}" != "localhost" ]]; then
    runtime_image="docker.io/${runtime_image}"
  fi

  docker image inspect "${image}" >/dev/null 2>&1 || docker pull "${image}"
  k3d image import "${image}" -c "${CLUSTER_NAME}"
  kubectl -n kube-system set image deployment/coredns coredns="${runtime_image}" >/dev/null
  kubectl -n kube-system patch deployment coredns --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' >/dev/null
  kubectl -n kube-system rollout status deployment/coredns --timeout=300s
}

preload_argocd_image() {
  echo "==> Preloading Argo CD image"
  docker pull "${ARGOCD_IMAGE}"
  k3d image import "${ARGOCD_IMAGE}" -c "${CLUSTER_NAME}"
}

create_cluster() {
  k3d cluster create "${CLUSTER_NAME}" --api-port "127.0.0.1:${CLUSTER_API_PORT}" --wait
}

fix_kubeconfig_server() {
  local server

  server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"${CLUSTER_CONTEXT}\")].cluster.server}" 2>/dev/null || true)"
  if [[ "${server}" == https://0.0.0.0:* ]]; then
    kubectl config set-cluster "${CLUSTER_CONTEXT}" --server="${server/0.0.0.0/127.0.0.1}" >/dev/null
  fi
}

use_cluster() {
  k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-switch-context >/dev/null
  fix_kubeconfig_server

  if kubectl cluster-info >/dev/null 2>&1; then
    return
  fi

  if [[ "${RESET_CLUSTER}" == "1" ]]; then
    echo "==> Recreating the unreachable k3d cluster"
    k3d cluster delete "${CLUSTER_NAME}"
    create_cluster
    k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-switch-context >/dev/null
    fix_kubeconfig_server
    return
  fi

  echo
  echo "The existing k3d cluster '${CLUSTER_NAME}' is not reachable."
  echo "To recreate it cleanly, run:"
  echo "  RESET_CLUSTER=1 ./scripts/install.sh"
  exit 1
}

echo "==> Base packages"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates git

echo "==> Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER" || true

if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
  sudo systemctl enable --now docker || true
else
  sudo service docker start || true
fi

if ! docker info >/dev/null 2>&1; then
  echo
  echo "Docker is installed, but this shell cannot use it yet."
  echo "Log out and back in, or run: newgrp docker"
  exit 1
fi

echo "==> kubectl"
if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

echo "==> k3d"
if ! command -v k3d >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo env PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" bash
fi

echo "==> Cluster"
if ! k3d cluster list 2>/dev/null | grep -qw "${CLUSTER_NAME}"; then
  create_cluster
else
  k3d cluster start "${CLUSTER_NAME}" >/dev/null 2>&1 || true
fi

use_cluster
kubectl cluster-info
preload_coredns_image
preload_argocd_image

echo "==> Namespaces"
ensure_namespace argocd
ensure_namespace dev
ensure_namespace gitlab

echo "==> Argo CD"
kubectl apply --server-side --force-conflicts -n argocd -f "${ARGOCD_MANIFEST_URL}"
kubectl delete pods -n argocd --all --ignore-not-found >/dev/null 2>&1 || true
wait_for_argocd

echo

echo "=================================================="
echo " Bonus cluster is ready."
echo " Next: ./deploy.sh"
echo "=================================================="
