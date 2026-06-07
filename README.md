# chat-app-infra

Infrastructure for deploying the multi-repo AI chat application on **Grid'5000** (Kubernetes on bare metal).

| Layer | Tool | Purpose |
|-------|------|---------|
| Provisioning | **Terraform** + [grid5000 provider](https://registry.terraform.io/providers/pmorillon/grid5000) | OAR reservation (`oarsub -t deploy ...`) + Kadeploy + RKE cluster |
| Configuration | **Ansible** | NVIDIA container toolkit, GPU device plugin, `kubectl apply` |
| Workloads | **Kubernetes** (Kustomize) | Gateway, worker, frontend, PostgreSQL, Redis, RabbitMQ, Ollama |

## Architecture on Kubernetes

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    chat-app namespace                    │
  Ingress / NodePort│                                                         │
        ┌───────────┼──────────► frontend:80                                    │
        │           │              │                                          │
        │           │              │ /api/* (ingress rewrite)                 │
        │           └──────────► gateway:8000 ◄──► redis / rabbitmq            │
        │                              │                                       │
        │                              ▼                                       │
        │                         worker ──────────► ollama:11434 (GPU)        │
        │                              │                                       │
        └──────────────────────────────┴──────────► postgres:5432              │
                    └─────────────────────────────────────────────────────────┘
```

## Docker images

Push these images to Docker Hub before deploying (`soufian1`):

| Image | Source repo |
|-------|-------------|
| `soufian1/chat-app-gateway:latest` | chat-app-gateway |
| `soufian1/chat-app-worker:latest` | chat-app-worker |
| `soufian1/chat-app-frontend:latest` | chat-app-frontend |

Build example:

```bash
docker build -t soufian1/chat-app-gateway:latest . && docker push soufian1/chat-app-gateway:latest
```

**Frontend note:** build with `VITE_API_URL=/api` so the browser uses the ingress path:

```bash
docker build --build-arg VITE_API_URL=/api -t soufian1/chat-app-frontend:latest .
```

## Prerequisites

1. **Grid'5000 account** with access to the [Lille](https://www.grid5000.fr/w/Lille:Hardware) site
2. SSH key registered on Grid'5000 (`~/.ssh/id_rsa.pub`)
3. Run all commands from a **Grid'5000 frontend** (not your laptop):

   ```bash
   ssh <your-login>@lille.frontend.grid5000.fr
   git clone <this-repo>
   cd chat-app-infra
   ```

4. Tools on the frontend: `terraform`, `kubectl`, `ansible`, `python3-yaml`

## Quick start

### 1. Configure Terraform

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

| Profile | `nodes_selector` | Use case |
|---------|------------------|----------|
| CPU (default) | `{cluster = 'chiclet'}` | Integration tests, no GPU |
| GPU | `{cluster = 'chifflot'}` | Ollama with NVIDIA P100/V100 |

Equivalent manual OAR command:

```bash
oarsub -t deploy -l walltime=4 -p "{cluster = 'chiclet'}" -r /nodes=4 \
  -n chat-app-k8s "sleep 4h"
```

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

After deploy, get node IPs from terraform output:

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

## Repository layout

```
terraform/          Grid'5000 OAR job + RKE Kubernetes cluster
ansible/            NVIDIA toolkit, device plugin, app rollout
kubernetes/
  base/             All manifests (namespace, secrets, deployments, ingress)
  overlays/
    grid5000/       Grid'5000 patches (GPU for Ollama, image tags)
    grid5000-cpu/   Same stack without GPU requests (chiclet cluster)
scripts/deploy.sh   End-to-end deploy helper
Makefile            Common targets
```

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

Internal DNS names match the docker-compose stacks (`postgres`, `redis`, `rabbitmq`, `ollama`).

## Secrets

Edit before production deploy:

- `kubernetes/overlays/grid5000/patches/secrets.yaml` — change `SECRET_KEY`
- `kubernetes/base/secrets.yaml` — default DB password (`chat`)

## CPU-only deploy (no GPU)

Use the `grid5000-cpu` overlay or the chiclet cluster selector:

```bash
kubectl apply -k kubernetes/overlays/grid5000-cpu
```

Ollama runs on CPU (slow but works for demos).

## GPU setup details

Grid'5000 nodes do not ship with the NVIDIA container toolkit. Ansible installs:

1. `nvidia-container-toolkit` on GPU nodes (`gpu_workers` group)
2. [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin) in the cluster
3. Node label `accelerator=nvidia-gpu` for Ollama scheduling

For GPU reservations, set in `terraform.tfvars`:

```hcl
nodes_selector = "{cluster = 'chifflot'}"
```

Ensure your Grid'5000 account has access to the chifflot cluster (P100/V100).

## Environment variables (mirrored from docker-compose)

**Gateway:** `SECRET_KEY`, `DATABASE_URL`, `REDIS_URL`, `RABBITMQ_URL`, `JWT_ALGORITHM`, `CORS_ORIGINS`

**Worker:** `DATABASE_URL`, `REDIS_URL`, `RABBITMQ_URL`, `OLLAMA_URL`, `LOG_LEVEL`

All wired via ConfigMap + Secret in `kubernetes/base/`.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Ollama pod pending | GPU node not labeled — run `ansible/playbooks/gpu-setup.yml` |
| Image pull errors | Push images to Docker Hub or set `imagePullSecrets` |
| PVC pending | Grid'5000 has no default StorageClass — RKE uses local-path; wait or check `kubectl get sc` |
| Frontend can't reach API | Rebuild frontend with `VITE_API_URL=/api` or use ingress on port 80 |

## Related repositories

| Repo | Role |
|------|------|
| chat-app-frontend | React UI |
| chat-app-gateway | FastAPI API |
| chat-app-worker | Queue consumer + Ollama client |
| **chat-app-infra** | This repo |

## License

MIT
