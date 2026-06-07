#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
KUBECONFIG_PATH="${TERRAFORM_DIR}/kube_config_cluster.yml"

usage() {
  cat <<'EOF'
Deploy the chat app on Grid'5000.

Usage:
  ./scripts/deploy.sh [phase]

Phases:
  all        Terraform + inventory + Ansible (default)
  terraform  Reserve nodes and create the Kubernetes cluster
  inventory  Generate Ansible inventory from terraform output
  ansible    Run Ansible playbooks (GPU setup + app deploy)
  k8s        Apply Kubernetes manifests only (cluster must exist)
  destroy    terraform destroy

Prerequisites:
  - Grid'5000 account and SSH key on the frontend
  - Docker images pushed to Docker Hub (soufian1/chat-app-*)
  - Run from a Grid'5000 frontend (e.g. lille.frontend.grid5000.fr)

EOF
}

phase="${1:-all}"

run_terraform() {
  echo "==> Terraform: reserving Grid'5000 nodes and deploying Kubernetes"
  cd "${TERRAFORM_DIR}"
  if [[ ! -f terraform.tfvars ]]; then
    echo "Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars and edit it."
    exit 1
  fi
  terraform init
  terraform apply
}

generate_inventory() {
  echo "==> Generating Ansible inventory from terraform output"
  cd "${TERRAFORM_DIR}"
  nodes_json="$(terraform output -json assigned_nodes 2>/dev/null || echo '[]')"
  inv_file="${ANSIBLE_DIR}/inventory/hosts.yml"

  python3 - <<PY
import json, yaml, os

nodes = json.loads('''${nodes_json}''')
if not nodes:
    raise SystemExit("No assigned nodes from terraform. Run terraform apply first.")

# First node: controlplane; rest: workers. Adjust gpu_workers manually for chifflot nodes.
inventory = {
    "all": {
        "children": {
            "k8s_controlplane": {"hosts": {nodes[0]: {}}},
            "k8s_workers": {"hosts": {n: {} for n in nodes[1:]}},
            "gpu_workers": {"hosts": {}},
        }
    }
}

# Auto-detect GPU nodes by hostname prefix on Lille
for n in nodes:
    if "chifflot" in n or "chuc" in n or "chicoree" in n:
        inventory["all"]["children"]["gpu_workers"]["hosts"][n] = {}

out = "${inv_file}"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    yaml.dump(inventory, f, default_flow_style=False)
print(f"Wrote {out}")
PY
}

run_ansible() {
  echo "==> Ansible: GPU setup + application deploy"
  export KUBECONFIG="${KUBECONFIG_PATH}"
  cd "${ANSIBLE_DIR}"
  if [[ ! -f inventory/hosts.yml ]]; then
    generate_inventory
  fi
  ansible-playbook playbooks/site.yml
}

apply_k8s() {
  echo "==> Applying Kubernetes manifests"
  export KUBECONFIG="${KUBECONFIG_PATH}"
  kubectl apply -k "${ROOT_DIR}/kubernetes/overlays/grid5000"
  kubectl -n chat-app get pods,svc,ingress
}

destroy() {
  cd "${TERRAFORM_DIR}"
  terraform destroy
}

case "${phase}" in
  all)
    run_terraform
    generate_inventory
    run_ansible
    ;;
  terraform) run_terraform ;;
  inventory) generate_inventory ;;
  ansible) run_ansible ;;
  k8s) apply_k8s ;;
  destroy) destroy ;;
  -h|--help|help) usage ;;
  *)
    echo "Unknown phase: ${phase}"
    usage
    exit 1
    ;;
esac
