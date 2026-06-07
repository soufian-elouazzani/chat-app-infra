output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file (relative to terraform/)"
  value       = "${path.module}/kube_config_cluster.yml"
}

output "assigned_nodes" {
  description = "Grid'5000 hostnames assigned to the OAR job"
  value       = module.k8s_cluster.assigned_nodes
}

output "next_steps" {
  description = "Commands to run after terraform apply"
  value       = <<-EOT
    export KUBECONFIG=${path.module}/kube_config_cluster.yml
    kubectl get nodes
    cd ../ansible && ansible-playbook -i inventory/hosts.yml playbooks/site.yml
  EOT
}
