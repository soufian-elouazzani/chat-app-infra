variable "site" {
  description = "Grid'5000 site (lille, rennes, nancy, ...)"
  type        = string
  default     = "lille"
}

variable "nodes_count" {
  description = "Number of nodes reserved for the Kubernetes cluster (1 controlplane/etcd + workers)"
  type        = number
  default     = 4
}

variable "walltime" {
  description = "OAR job duration (hours, Grid'5000 notation)"
  type        = string
  default     = "4"
}

variable "nodes_selector" {
  description = "OAR SQL nodes selector in curly braces. Use chifflot@lille for GPU nodes."
  type        = string
  default     = "{cluster = 'chiclet'}"
}

variable "kubernetes_version" {
  description = "RKE Kubernetes version (see rancher/terraform-provider-rke releases)"
  type        = string
  default     = "v1.22.4-rancher1-1"
}

variable "oar_job_name" {
  description = "Name shown in OAR for this reservation"
  type        = string
  default     = "chat-app-k8s"
}

variable "ssh_key_path" {
  description = "SSH private key used to access reserved nodes"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "deb_extra_pkgs" {
  description = "Extra Debian packages installed on every cluster node during deployment"
  type        = list(string)
  default     = ["curl", "jq", "python3-pip"]
}
