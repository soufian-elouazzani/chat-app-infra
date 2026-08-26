# AI Chat App — Infrastructure

Infrastructure-as-code for a **multi-repo, ChatGPT-style AI chat platform** deployed on **[Grid'5000](https://www.grid5000.fr/)** (bare-metal Kubernetes).

This repository is the **DevOps / platform** side of the project: provisioning, configuration management, GPU enablement, and Kubernetes manifests. The application itself lives in three sibling repositories.

> **Deep dives:**  
> - [How_Grid5000_Works.md](./How_Grid5000_Works.md) — Grid'5000, Lille clusters, SSH, OAR, and how to connect  
> - [How_The_App_Infra_Works.md](./How_The_App_Infra_Works.md) — Terraform, Ansible, Kubernetes, and how every layer connects

---

## Related repositories

| Repository | Role | Stack | Link |
|------------|------|-------|------|
| **chat-app-frontend** | React chat UI (sessions, messages, polling) | React, Vite, TypeScript | [github.com/soufian-elouazzani/chat-app-frontend](https://github.com/soufian-elouazzani/chat-app-frontend) |
| **chat-app-gateway** | API gateway (auth, sessions, task status) | FastAPI, JWT, Redis, RabbitMQ | [github.com/soufian-elouazzani/chat-app-gateway](https://github.com/soufian-elouazzani/chat-app-gateway) |
| **chat-app-worker** | Async inference worker (queue → Ollama) | Python, RabbitMQ, Ollama | [github.com/soufian-elouazzani/chat-app-worker](https://github.com/soufian-elouazzani/chat-app-worker) |
| **chat-app-infra** | Provisioning + K8s deploy (this repo) | Terraform, Ansible, Kustomize | [github.com/soufian-elouazzani/chat-app-infra](https://github.com/soufian-elouazzani/chat-app-infra) |

Each app repo has its own README (architecture, API, local run). This repo focuses on **how the platform is provisioned and deployed**.

---

## What this project demonstrates

- **Infrastructure as Code** — Terraform reserves Grid'5000 nodes and creates an RKE Kubernetes cluster
- **Configuration management** — Ansible installs the NVIDIA stack and applies Kustomize overlays
- **Kubernetes on bare metal** — multi-service stack with Ingress, PVCs, GPU scheduling
- **Async AI architecture** — frontend → gateway → RabbitMQ → worker → Ollama (GPU)
- **Environment overlays** — GPU (`grid5000`) vs CPU-only (`grid5000-cpu`) deployments

---

## System overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Grid'5000 bare-metal nodes                       │
│                                                                          │
│   Terraform ──► OAR reservation + Kadeploy + RKE Kubernetes cluster      │
│   Ansible   ──► NVIDIA toolkit / device plugin + kubectl apply           │
│                                                                          │
│   ┌──────────────────────── namespace: chat-app ────────────────────────┐  │
│   │  Ingress / NodePort                                              │  │
│   │       │                                                          │  │
│   │       ├──────────► frontend:80                                   │  │
│   │       │                 │ /api/* (ingress rewrite)               │  │
│   │       └──────────► gateway:8000 ◄──► redis / rabbitmq            │  │
│   │                          │                                       │  │
│   │                          ▼                                       │  │
│   │                     worker ──────────► ollama:11434 (GPU)        │  │
│   │                          │                                       │  │
│   │                          └──────────► postgres:5432              │  │
│   └──────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

| Layer | Tool | Purpose |
|-------|------|---------|
| 1 — Provisioning | **Terraform** + [grid5000 provider](https://registry.terraform.io/providers/pmorillon/grid5000) | OAR reservation + Kadeploy + RKE cluster |
| 2 — Configuration | **Ansible** | NVIDIA container toolkit, GPU device plugin, `kubectl apply` |
| 3 — Workloads | **Kubernetes** (Kustomize) | Gateway, worker, frontend, PostgreSQL, Redis, RabbitMQ, Ollama |

For a detailed explanation of each layer, see **[How_The_App_Infra_Works.md](./How_The_App_Infra_Works.md)**.

---

## Repository layout

```
terraform/              Layer 1 — OAR + Kadeploy + RKE Kubernetes cluster
ansible/                Layer 2 — NVIDIA toolkit, device plugin, app rollout
kubernetes/
  base/                 All manifests (namespace, secrets, deployments, ingress)
  overlays/
    grid5000/           GPU overlay (Ollama + nvidia.com/gpu)
    grid5000-cpu/       Same stack without GPU requests
scripts/deploy.sh       End-to-end deploy helper
Makefile                Common targets
How_Grid5000_Works.md        Grid'5000 guide (clusters, SSH, OAR)
How_The_App_Infra_Works.md   Architecture deep dive
```

---

## Docker images

Build and push these images to Docker Hub before deploying (`soufian1`):

| Image | Source repository |
|-------|-------------------|
| `soufian1/chat-app-gateway:latest` | [chat-app-gateway](https://github.com/soufian-elouazzani/chat-app-gateway) |
| `soufian1/chat-app-worker:latest` | [chat-app-worker](https://github.com/soufian-elouazzani/chat-app-worker) |
| `soufian1/chat-app-frontend:latest` | [chat-app-frontend](https://github.com/soufian-elouazzani/chat-app-frontend) |

```bash
# Example (from each app repo)
docker build -t soufian1/chat-app-gateway:latest . && docker push soufian1/chat-app-gateway:latest
```

**Frontend:** build with `VITE_API_URL=/api` so the browser uses the Ingress path:

```bash
docker build --build-arg VITE_API_URL=/api -t soufian1/chat-app-frontend:latest .
```

---

## Prerequisites

1. **Grid'5000 account** with access to the [Lille](https://www.grid5000.fr/w/Lille:Hardware) site
2. SSH key registered on Grid'5000 (`~/.ssh/id_rsa.pub`)
3. Run all commands from a **Grid'5000 frontend** (not your laptop):

   ```bash
   ssh <your-login>@lille.frontend.grid5000.fr
   git clone https://github.com/soufian-elouazzani/chat-app-infra.git
   cd chat-app-infra
   ```

4. Tools on the frontend: `terraform`, `kubectl`, `ansible`, `python3-yaml`

---

## Quick start

### 1. Configure Terraform

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

| Profile | `nodes_selector` | Use case |
|---------|------------------|----------|
| CPU (default) | `{cluster = 'chiclet'}` | Integration tests, no GPU |
| GPU | `{cluster = 'chifflot'}` | Ollama with NVIDIA P100/V100 |

### 2. Deploy everything

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh all
```

Or step by step:

```bash
make tf-apply      # reserve nodes + create K8s cluster (~15–30 min)
make inventory     # write ansible/inventory/hosts.yml from terraform output
make ansible       # NVIDIA setup + kubectl apply
```

### 3. Access the app

```bash
export KUBECONFIG=$PWD/terraform/kube_config_cluster.yml
kubectl get nodes -o wide
kubectl -n chat-app get ingress,svc
```

| Method | URL |
|--------|-----|
| Ingress (recommended) | `http://<any-node-ip>/` (API at `/api/...`) |
| NodePort fallback | Frontend `http://<node-ip>:30080`, API `http://<node-ip>:30800` |

### 4. Pull an Ollama model

```bash
kubectl -n chat-app exec deploy/ollama -- ollama pull llama3.2:3b
```

Or set `ollama_model` in `ansible/group_vars/all.yml` before running Ansible.

### 5. Tear down

```bash
make destroy
# or: ./scripts/deploy.sh destroy
```

---

## Kubernetes services

| Service | Image | Port |
|---------|-------|------|
| gateway | `soufian1/chat-app-gateway` | 8000 |
| worker | `soufian1/chat-app-worker` | — |
| frontend | `soufian1/chat-app-frontend` | 80 |
| postgres | `postgres:16-alpine` | 5432 |
| redis | `redis:7-alpine` | 6379 |
| rabbitmq | `rabbitmq:3.13-management` | 5672 / 15672 |
| ollama | `ollama/ollama:latest` | 11434 |

Internal DNS names match docker-compose (`postgres`, `redis`, `rabbitmq`, `ollama`).

---

## CPU-only vs GPU

**CPU-only** (chiclet / demos):

```bash
kubectl apply -k kubernetes/overlays/grid5000-cpu
```

**GPU** (chifflot — P100/V100): set in `terraform.tfvars`:

```hcl
nodes_selector = "{cluster = 'chifflot'}"
```

Ansible then installs:

1. `nvidia-container-toolkit` on GPU nodes
2. [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin)
3. Node label `accelerator=nvidia-gpu` for Ollama scheduling

---

## Secrets

Edit before a real deploy:

- `kubernetes/overlays/grid5000/patches/secrets.yaml` — change `SECRET_KEY`
- `kubernetes/base/secrets.yaml` — default DB password (`chat`)

Gateway env: `SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, `RABBITMQ_URL`, `JWT_ALGORITHM`, `CORS_ORIGINS`  
Worker env: `DATABASE_URL`, `REDIS_URL`, `RABBITMQ_URL`, `OLLAMA_URL`, `LOG_LEVEL`  

All wired via ConfigMap + Secret in `kubernetes/base/`.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Ollama pod pending | GPU node not labeled — run `ansible/playbooks/gpu-setup.yml` |
| Image pull errors | Push images to Docker Hub or set `imagePullSecrets` |
| PVC pending | RKE uses local-path; wait or check `kubectl get sc` |
| Frontend can't reach API | Rebuild frontend with `VITE_API_URL=/api` or use ingress on port 80 |

---

## Documentation map

| Document | Content |
|----------|---------|
| **This README** | Project overview, related repos, quick deploy |
| **[How_Grid5000_Works.md](./How_Grid5000_Works.md)** | Grid'5000 platform, Lille clusters, SSH/OAR, connection guide |
| **[How_The_App_Infra_Works.md](./How_The_App_Infra_Works.md)** | Layer-by-layer infra explanation (Terraform → Ansible → K8s) |
| [Frontend README](https://github.com/soufian-elouazzani/chat-app-frontend#readme) | UI, features, message flow |
| [Gateway README](https://github.com/soufian-elouazzani/chat-app-gateway#readme) | API, auth, async task contract |
| [Worker README](https://github.com/soufian-elouazzani/chat-app-worker#readme) | Queue consumer, Ollama integration |

---

## License

MIT
