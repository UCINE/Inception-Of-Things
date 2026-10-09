#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="/tmp/iot-gitlab-repo"

CLUSTER_NAME="iot"
CLUSTER_CONTEXT="k3d-${CLUSTER_NAME}"
GITLAB_PASSWORD="iotgitlab"
GITLAB_IMAGE="${GITLAB_IMAGE:-gitlab/gitlab-ce:9.5.10-ce.0}"
PLAYGROUND_IMAGES=("docker.io/wil42/playground:v1" "docker.io/wil42/playground:v2")
GIT_BRANCH="iot"
ALLOW_UNPROTECTED_PUSH="${ALLOW_UNPROTECTED_PUSH:-1}"
GITLAB_LOCAL_PORT="${GITLAB_LOCAL_PORT:-8081}"
GITLAB_LOCAL_URL="http://127.0.0.1:${GITLAB_LOCAL_PORT}"
PORT_FORWARD_PID=""

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run this script with sudo."
  echo "Run it as your normal user: ./scripts/deploy.sh"
  exit 1
fi

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

fix_kubeconfig_server() {
  local server

  server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"${CLUSTER_CONTEXT}\")].cluster.server}" 2>/dev/null || true)"
  if [[ "${server}" == https://0.0.0.0:* ]]; then
    kubectl config set-cluster "${CLUSTER_CONTEXT}" --server="${server/0.0.0.0/127.0.0.1}" >/dev/null
  fi
}

prepare_cluster() {
  echo "==> Checking the k3d cluster context"

  if command -v k3d >/dev/null 2>&1 && k3d cluster list 2>/dev/null | grep -qw "${CLUSTER_NAME}"; then
    k3d cluster start "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-switch-context >/dev/null
    fix_kubeconfig_server
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl cannot reach the k3d cluster."
    echo "Run RESET_CLUSTER=1 ./scripts/install.sh, then run this script again."
    exit 1
  fi
}

preload_gitlab_image() {
  echo "==> Preloading GitLab image"
  docker image inspect "${GITLAB_IMAGE}" >/dev/null 2>&1 || docker pull "${GITLAB_IMAGE}"
  if ! image_is_in_cluster "${GITLAB_IMAGE}"; then
    k3d image import "${GITLAB_IMAGE}" -c "${CLUSTER_NAME}"
  fi
}

preload_playground_images() {
  echo "==> Preloading playground app images"

  local image
  local short_image
  for image in "${PLAYGROUND_IMAGES[@]}"; do
    docker image inspect "${image}" >/dev/null 2>&1 || docker pull "${image}"
    if ! image_is_in_cluster "${image}"; then
      k3d image import "${image}" -c "${CLUSTER_NAME}"
    fi
    short_image="${image#docker.io/}"
    docker exec "k3d-${CLUSTER_NAME}-server-0" \
      ctr -n k8s.io images tag "docker.io/${short_image}" "${short_image}" >/dev/null 2>&1 || true
  done
}

image_is_in_cluster() {
  local image="$1"
  local repo="${image%:*}"
  local tag="${image##*:}"

  docker exec "k3d-${CLUSTER_NAME}-server-0" crictl images |
    awk -v repo="${repo}" -v tag="${tag}" '
      NR > 1 && ($1 == repo || $1 == "docker.io/" repo) && $2 == tag { found = 1 }
      END { exit found ? 0 : 1 }
    '
}

gitlab_pod() {
  kubectl -n gitlab get pod -l app=gitlab --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}'
}

wait_for_gitlab() {
  echo "==> Waiting for GitLab Rails to be ready"

  local pod
  for _ in $(seq 1 80); do
    pod="$(gitlab_pod 2>/dev/null || true)"
    if [[ -n "${pod}" ]] &&
       kubectl -n gitlab exec "${pod}" -- gitlab-rails runner "puts 'ready'" >/dev/null 2>&1; then
      return
    fi
    sleep 15
  done

  echo
  echo "GitLab did not become ready in time."
  kubectl get pods -n gitlab -o wide || true
  echo
  kubectl logs -n gitlab -l app=gitlab --tail=120 || true
  exit 1
}

create_gitlab_project() {
  echo "==> Creating the local GitLab project root/iot"

  local pod
  pod="$(gitlab_pod)"

  kubectl -n gitlab exec "${pod}" -- env ALLOW_UNPROTECTED_PUSH="${ALLOW_UNPROTECTED_PUSH}" gitlab-rails runner "
    root = User.find_by(username: 'root')
    root.password = 'iotgitlab'
    root.password_confirmation = 'iotgitlab'
    root.save!

    settings = ApplicationSetting.current
    if settings.default_branch_protection.to_i != 0
      unless ENV['ALLOW_UNPROTECTED_PUSH'] == '1'
        abort 'GitLab protects the first branch by default. Re-run with ALLOW_UNPROTECTED_PUSH=1 ./scripts/deploy.sh'
      end
      settings.update_attributes!(default_branch_protection: 0)
    end

    namespace = root.namespace
    project = Project.where(namespace_id: namespace.id, path: 'iot').first

    unless project
      project = Project.create!(
        name: 'iot',
        path: 'iot',
        namespace: namespace,
        creator: root,
        visibility_level: 20
      )
    end

    project.update_attributes!(visibility_level: 20)
    project.create_repository unless project.repository_exists?
    puts project.full_path
  "
}

start_gitlab_port_forward() {
  echo "==> Opening a temporary GitLab port-forward on localhost:${GITLAB_LOCAL_PORT}"

  if curl -fsS "${GITLAB_LOCAL_URL}/users/sign_in" >/dev/null 2>&1; then
    return
  fi

  kubectl -n gitlab port-forward svc/gitlab "${GITLAB_LOCAL_PORT}:80" >/tmp/iot-gitlab-port-forward.log 2>&1 &
  PORT_FORWARD_PID="$!"

  for _ in $(seq 1 40); do
    if curl -fsS "${GITLAB_LOCAL_URL}/users/sign_in" >/dev/null 2>&1; then
      return
    fi
    sleep 3
  done

  echo "Could not reach GitLab through the local port-forward."
  cat /tmp/iot-gitlab-port-forward.log || true
  exit 1
}

push_app_to_gitlab() {
  echo "==> Pushing p3/app to the local GitLab repository"

  rm -rf "${WORK_DIR}"
  git clone "http://root:${GITLAB_PASSWORD}@127.0.0.1:${GITLAB_LOCAL_PORT}/root/iot.git" "${WORK_DIR}"

  mkdir -p "${WORK_DIR}/p3"
  rm -rf "${WORK_DIR}/p3/app"
  cp -R "${ROOT_DIR}/p3/app" "${WORK_DIR}/p3/app"

  cd "${WORK_DIR}"
  git checkout -B "${GIT_BRANCH}"
  git config user.email "iot@example.local"
  git config user.name "IoT Bonus"
  git add p3/app

  if git diff --cached --quiet; then
    echo "The GitLab repository already has the current app manifests."
  else
    git commit -m "Add playground app"
    git push origin "${GIT_BRANCH}"
  fi
}

prepare_cluster
preload_gitlab_image
preload_playground_images

echo "==> Deploying GitLab into the cluster"
kubectl apply -f "${SCRIPT_DIR}/../confs/gitlab.yaml"
kubectl -n gitlab set image deployment/gitlab gitlab="${GITLAB_IMAGE}"

echo "==> Waiting for the GitLab pod"
kubectl -n gitlab rollout status deployment/gitlab --timeout=1200s
wait_for_gitlab
create_gitlab_project
start_gitlab_port_forward
push_app_to_gitlab

echo "==> Registering the Argo CD application"
kubectl apply -f "${SCRIPT_DIR}/../confs/application.yaml"
kubectl -n dev delete pod -l app=wil-playground --ignore-not-found >/dev/null 2>&1 || true

echo "==> Waiting for the app in dev"
for i in $(seq 1 30); do
  if kubectl -n dev get deployment wil-playground >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
kubectl -n dev rollout status deployment/wil-playground --timeout=300s || true

echo
kubectl get ns

echo
kubectl get pods -n gitlab

echo
kubectl get pods -n dev

echo
cat <<'EOF'
--------------------------------------------------------------------
Access Argo CD with:
  kubectl port-forward svc/argocd-server -n argocd 8080:443

Access GitLab with:
  kubectl port-forward svc/gitlab -n gitlab 8081:80

GitLab login:
  user: root
  password: iotgitlab

This local lab GitLab has default branch protection disabled so the script
can push the first app branch automatically.

The Argo CD app now reads from:
  http://gitlab.gitlab.svc.cluster.local/root/iot.git

To demonstrate v2, edit p3/app/deployment.yaml in GitLab and change:
  docker.io/wil42/playground:v1 -> docker.io/wil42/playground:v2
--------------------------------------------------------------------
EOF
