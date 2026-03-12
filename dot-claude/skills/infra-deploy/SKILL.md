---
name: infra-deploy
description: Infrastructure as Code workflows with Terraform, Ansible, Docker, and Kubernetes. Use when provisioning, configuring, deploying, or managing infrastructure.
paths: ["**/*.tf", "**/*.tfvars", "**/*.hcl", "**/ansible*", "**/playbooks/**", "**/*.yaml", "**/*.yml", "**/k8s/**", "**/helm/**"]
---

# Infrastructure Workflows

## Terraform
1. `terraform fmt -recursive` — format all .tf files
2. `tflint` — lint for errors and best practices
3. `terraform validate` — syntax validation
4. `terraform plan -out=plan.tfplan` — preview changes (ALWAYS do this first)
5. `infracost breakdown --path=plan.tfplan` — estimate cost impact
6. Only after review: `terraform apply plan.tfplan`

NEVER run `terraform apply -auto-approve` or `terraform destroy` without explicit operator approval.

## Ansible
1. `ansible-lint` — lint playbooks
2. `ansible-playbook --check -i inventory site.yml` — dry run
3. `ansible-playbook -i inventory site.yml` — actual run

## Docker
1. `hadolint Dockerfile` — lint before building
2. `docker build -t <name>:<tag> .` — build image
3. `trivy image <name>:<tag>` — scan for vulnerabilities
4. `dive <name>:<tag>` — analyze layer efficiency
5. `docker compose up -d` — deploy

## Kubernetes
1. `kubectl get pods -A` — cluster overview
2. `k9s` — interactive management
3. `stern <pod-prefix>` — tail logs from multiple pods
4. `helm list -A` — check installed charts

## Hetzner Cloud
Run `hcloud --help` for available commands.
Common: `hcloud server list`, `hcloud server create`, `hcloud firewall list`

## Rules
- ALWAYS plan before apply
- ALWAYS scan images before deploying
- ALWAYS lint IaC files before committing
- Use `sops` or `age` for secrets, never plaintext
