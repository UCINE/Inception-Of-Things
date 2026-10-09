# Inception Of Things
Quick reference for K3s, Vagrant, K3d, CI, and Argo CD.

---

## K3s
**What it is:** A lightweight, certified Kubernetes distribution packaged as a single binary.

- Built for edge, IoT, CI, and resource-constrained environments
- Bundles control plane, containerd, and networking into one process
- Uses SQLite by default (or etcd/PostgreSQL/MySQL for HA)
- Fully API-compatible with upstream Kubernetes

---

## Vagrant
**What it is:** A tool for building reproducible virtual machine environments from code.

- Defined via a `Vagrantfile` (Ruby syntax)
- Uses **boxes** (base VM images) and **providers** (VirtualBox, VMware, Hyper-V)
- **Provisioners** auto-configure the VM (shell, Ansible, Chef, Puppet)
- Core commands: `vagrant up`, `vagrant ssh`, `vagrant halt`, `vagrant destroy`

---

## K3d
**What it is:** A tool that runs K3s clusters inside Docker containers.

- "K3s in Docker" — each node is a Docker container, not a VM
- Spins up multi-node clusters in seconds
- Includes a built-in load balancer for multi-server setups
- Supports a local Docker registry for pushing images directly into the cluster
- Core command: `k3d cluster create`, `k3d cluster delete`

---

## Continuous Integration (CI)
**What it is:** A practice of frequently merging code with automated build/test verification.

- Developers push small, frequent changes
- CI server automatically builds, tests, lints, and packages the code
- Fast feedback — broken builds are fixed immediately
- Common tools: GitHub Actions, GitLab CI, Jenkins, CircleCI

---

## Argo CD
**What it is:** A GitOps-based Continuous Delivery tool for Kubernetes.

- Git repo = single source of truth for desried cluster state
- Continuously compares Git (desired) vs. cluster (actual) state
- Auto-syncs or flags drift; supports self-healing and easy rollback via Git history
- Core concept: **Applications** (map a Git path → cluster destination)

---

## How They Fit Together

| Tool | Role |
|---|---|
| Vagrant | Provision local/dev VMs (general purpose) |
| K3s | Lightweight Kubernetes distro (runs anywhere: VM, bare metal, container) |
| K3d | Run K3s clusters locally inside Docker for fast dev/testing |
| CI | Build, test, and package application code/images |
| Argo CD | Deploy those images to Kubernetes clusters via GitOps |

**Typical flow:**
```
Code push → CI (build, test, push image) →
Update image tag in GitOps repo →
Argo CD detects change → deploys to K3s/K3d cluster
```
