# Bonus Defense Guide

This file follows the bonus correction checklist. Use it during defense to explain what the bonus does and how to verify it.

## 1. Show The Bonus Files

Run from the repository root:

```bash
find bonus -maxdepth 3 -type f -print
```

Explain each file:

- `bonus/scripts/install.sh`: installs the tools needed for the local lab, creates/repairs the `iot` k3d cluster, creates the `argocd`, `dev`, and `gitlab` namespaces, preloads Argo CD, and installs Argo CD.
- `bonus/scripts/deploy.sh`: deploys local GitLab, creates the `root/iot` repository, pushes the app manifests into local GitLab, registers the Argo CD Application, and preloads the app images used for the v1/v2 demo.
- `bonus/confs/gitlab.yaml`: Kubernetes manifest for the local GitLab service and deployment in the `gitlab` namespace.
- `bonus/confs/application.yaml`: Argo CD Application manifest. It points Argo CD to the local GitLab repository.

## 2. Prove GitLab Runs Locally

Check the namespace, pod, and service:

```bash
kubectl get ns
kubectl get pods -n gitlab
kubectl get svc -n gitlab
```

Expected result:

- Namespace `gitlab` exists.
- GitLab pod is `Running`.
- Service `gitlab` exists.

Open GitLab in the browser:

```bash
kubectl port-forward svc/gitlab -n gitlab 8081:80
```

Then open:

```text
http://localhost:8081
```

Login:

```text
user: root
password: iotgitlab
```

Explanation to give:

GitLab is not GitHub and not an online GitLab instance. It runs locally inside the k3d cluster, in the `gitlab` namespace. Browser access is only through `kubectl port-forward`.

## 3. Test GitLab With A New Repository

The evaluator may ask to create a new repository and push code.

In the GitLab UI:

1. Click `New project`.
2. Create a blank project.
3. Name it `test`.
4. Create it under the `root` user.

Then push a simple file:

```bash
mkdir /tmp/gitlab-test
cd /tmp/gitlab-test
git init
echo "hello gitlab" > README.md
git add README.md
git commit -m "test gitlab"
git branch -M iot
git remote add origin http://root:iotgitlab@127.0.0.1:8081/root/test.git
git push -u origin iot
```

Refresh the GitLab browser page and confirm `README.md` appears.

If GitLab blocks the first push because of branch protection, explain that GitLab protects first/default branches by default. For the automated `root/iot` lab repository, `deploy.sh` disables that default protection in the local lab GitLab so the demo can push the app branch.

## 4. Prove Argo CD Uses Local GitLab

Show the Argo CD Application config:

```bash
cat bonus/confs/application.yaml
```

Important lines:

```yaml
repoURL: http://gitlab.gitlab.svc.cluster.local/root/iot.git
targetRevision: iot
path: p3/app
```

Explanation to give:

- `gitlab.gitlab.svc.cluster.local` is the Kubernetes service DNS name for the local GitLab service.
- `root/iot.git` is the repository created in local GitLab.
- `targetRevision: iot` means Argo CD tracks the `iot` branch.
- `path: p3/app` means Argo CD deploys the same app manifests used in Part 3.

Check the live Argo CD object:

```bash
kubectl get application -n argocd
kubectl describe application wil-playground -n argocd
```

Expected result:

- Application exists.
- Repository URL is the local GitLab service URL.
- Sync status is `Synced`.

## 5. Prove Part 3 Still Works

Check the app in the `dev` namespace:

```bash
kubectl get pods -n dev
kubectl get svc -n dev
```

Expected result:

- `wil-playground` pod is `Running`.
- `wil-playground` service exists.

Access the app:

```bash
kubectl port-forward svc/wil-playground -n dev 8888:8888
```

Then test in another terminal:

```bash
curl http://localhost:8888
```

Expected v1 result:

```json
{"status":"ok","message":"v1"}
```

## 6. Demonstrate The Version Change

In GitLab UI, open:

```text
root / iot / p3 / app / deployment.yaml
```

Edit the image:

```yaml
image: docker.io/wil42/playground:v1
```

Change it to:

```yaml
image: docker.io/wil42/playground:v2
```

Commit the change to branch:

```text
iot
```

Watch the rollout:

```bash
kubectl get pods -n dev -w
```

Or check Argo CD:

```bash
kubectl get application wil-playground -n argocd
kubectl describe application wil-playground -n argocd
```

Test the app again:

```bash
curl http://localhost:8888
```

Expected v2 result:

```json
{"status":"ok","message":"v2"}
```

If Argo CD does not sync immediately, force a refresh:

```bash
kubectl annotate application wil-playground -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## 7. Useful Browser Access Commands

GitLab:

```bash
kubectl port-forward svc/gitlab -n gitlab 8081:80
```

Open:

```text
http://localhost:8081
```

Argo CD:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open:

```text
https://localhost:8080
```

App:

```bash
kubectl port-forward svc/wil-playground -n dev 8888:8888
```

Open:

```text
http://localhost:8888
```

## 8. Important Explanations

Why images are preloaded:

The network sometimes times out when the k3d node pulls images from Docker Hub or Quay. The scripts pull images on the host and import them into k3d so the demo is reliable.

Why the app uses `docker.io/wil42/playground:v1`:

The k3d node stores the preloaded image under the fully qualified name `docker.io/wil42/playground:v1`. Using that exact name lets Kubernetes find the local image.

Why `imagePullPolicy: Never` is used:

It tells Kubernetes not to pull from Docker Hub during the defense. The image is already imported into the local k3d node by `deploy.sh`.

Why branch `iot` is used:

Old GitLab protects the first/default branch by default. The lab uses branch `iot` and Argo CD tracks that branch.

Why GitLab version is `9.5.10-ce.0`:

Docker Hub no longer serves an active `gitlab/gitlab-ce:9.6.0-ce.0` image. The closest active old official GitLab CE tag found was `9.5.10-ce.0`.

## 9. Bonus Pass Criteria

The bonus should be considered valid when:

- The `bonus` folder contains clear scripts and configuration files.
- GitLab runs locally in the `gitlab` namespace.
- A repository can be created and code can be pushed to local GitLab.
- Argo CD uses the local GitLab repository, not GitHub.
- The Part 3 application runs in `dev`.
- Changing the app image from v1 to v2 in local GitLab causes Argo CD to sync and the app output changes to v2.
