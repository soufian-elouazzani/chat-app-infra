.PHONY: help init tf-apply tf-destroy inventory ansible k8s deploy destroy

KUBECONFIG := $(CURDIR)/terraform/kube_config_cluster.yml
export KUBECONFIG

help:
	@echo "Targets:"
	@echo "  init        terraform init"
	@echo "  tf-apply    reserve Grid'5000 nodes + create K8s cluster"
	@echo "  tf-destroy  destroy cluster and release OAR job"
	@echo "  inventory   generate ansible/inventory/hosts.yml from terraform"
	@echo "  ansible     run full ansible site playbook"
	@echo "  k8s         kubectl apply -k kubernetes/overlays/grid5000"
	@echo "  deploy      full deploy (terraform + inventory + ansible)"
	@echo "  destroy     alias for tf-destroy"

init:
	cd terraform && terraform init

tf-apply:
	@test -f terraform/terraform.tfvars || (echo "Copy terraform/terraform.tfvars.example first" && exit 1)
	cd terraform && terraform apply

tf-destroy:
	cd terraform && terraform destroy

inventory:
	./scripts/deploy.sh inventory

ansible:
	./scripts/deploy.sh ansible

k8s:
	kubectl apply -k kubernetes/overlays/grid5000

deploy:
	chmod +x scripts/deploy.sh
	./scripts/deploy.sh all

destroy: tf-destroy
