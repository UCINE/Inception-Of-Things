#!/usr/bin/env bash
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Registering the Argo CD Application"
kubectl apply -f "${SCRIPT_DIR}/../confs/application.yaml"

echo "==> Waiting for Argo CD to deploy the app into 'dev'..."

for i in $(seq 1 30); do
  if kubectl -n dev get deployment wil-playground >/dev/null 2>&1; then break; fi
  sleep 5
done
kubectl -n dev rollout status deployment/wil-playground --timeout=300s || true

echo
kubectl get ns
echo
kubectl get pods -n dev
echo
cat <<'EOF'
--------------------------------------------------------------------
Access the Argo CD web UI (https://localhost:8080):
Zqiy3CT1Hfj0dJlI

Access the application (http://localhost:8888):
    kubectl port-forward svc/wil-playground -n dev 8888:8888
    
--------------------------------------------------------------------
EOF
