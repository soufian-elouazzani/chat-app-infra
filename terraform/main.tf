# Provisions a bare-metal Kubernetes cluster on Grid'5000 via OAR + Kadeploy + RKE.
#
# Run from a Grid'5000 frontend (e.g. ssh lille.frontend.grid5000.fr):
#   cd terraform && terraform init && terraform apply
#
# Equivalent manual reservation:
#   oarsub -t deploy -l walltime=4 -p "{cluster = 'chiclet'}" -r /nodes=4 \
#     -n chat-app-k8s "sleep 4h"

module "k8s_cluster" {
  source  = "pmorillon/k8s-cluster/grid5000"
  version = "~> 0.0.1"

  site               = var.site
  nodes_count        = var.nodes_count
  walltime           = var.walltime
  nodes_selector     = var.nodes_selector
  kubernetes_version = var.kubernetes_version
  oar_job_name       = var.oar_job_name
  ssh_key_path       = var.ssh_key_path
  deb_extra_pkgs     = var.deb_extra_pkgs
  oar_extra_types    = ["deploy"]
}
