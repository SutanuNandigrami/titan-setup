---
paths: ["**/*.tf", "**/*.tfvars", "**/*.hcl", "**/terraform/**"]
---
# Terraform Rules
- Always `terraform fmt` before commit
- Always `terraform plan` before `terraform apply` — never `-auto-approve` in production
- Run `tflint` and `trivy config .` before applying
- Use `infracost` to estimate cost impact
- One resource per file where practical
- Use modules for reusable infrastructure
- Secrets via `sops` or `infisical` — never plaintext in `.tf` files
- State files (`.tfstate`) must never be committed
