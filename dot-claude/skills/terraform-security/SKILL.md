---
name: terraform-security
description: Terraform security scanning, state management, secrets handling, IAM least privilege, and IaC hardening. Use when writing, auditing, or deploying Terraform configs.
paths: ["**/*.tf", "**/*.tfvars", "**/*.hcl", "**/terraform.tfvars*", "**/terraform/**"]
---

# Terraform Security

## Pre-Commit Scanning

```bash
terraform fmt -check -recursive .                      # Format check (fail CI on diff)
terraform validate                                     # Syntax + provider validation
tflint                                                 # Lint rules
tfsec . --minimum-severity medium                      # Security misconfigs (fast)
checkov -d . --framework terraform --quiet             # Comprehensive policy check

# All in CI:
terraform fmt -check -recursive . && terraform validate && tflint && \
  tfsec . --minimum-severity medium && checkov -d . --framework terraform --quiet
```

## Secrets — Never Hardcode

```hcl
# BAD — gitleaks will catch this
variable "db_password" { default = "admin123" }  # ❌

# GOOD — external supply
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true     # Redacted from plan output + logs
  # Supply via: TF_VAR_db_password or secrets.tfvars (gitignored)
}

# GOOD — AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "prod/db/password"
}

# GOOD — HashiCorp Vault
data "vault_generic_secret" "db" {
  path = "secret/prod/database"
}
```

**.gitignore:**
```
*.tfvars
!example.tfvars   # Commit template, not real values
terraform.tfstate*
.terraform/
```

## State File Security

State contains **plaintext secrets** — always encrypt with access controls.

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state-<account-id>"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:..."    # SSE-KMS
    dynamodb_table = "terraform-locks"    # Prevent concurrent apply
  }
}

# Block ALL public access
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning for rollback
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

# Access logging (audit trail)
resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "state-access/"
}
```

## IAM Least Privilege

```hcl
# BAD
Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]  # ❌ Never

# GOOD — specific actions + resources + conditions
Statement = [
  {
    Sid    = "ReadOnlyData"
    Effect = "Allow"
    Action = ["s3:GetObject", "s3:ListBucket"]
    Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
  },
  {
    Sid    = "DecryptOnly"
    Effect = "Allow"
    Action = ["kms:Decrypt"]
    Resource = aws_kms_key.data.arn
    Condition = {
      StringEquals = { "kms:ViaService" = "s3.us-east-1.amazonaws.com" }
    }
  },
  {
    Sid    = "DenyUnencryptedUploads"
    Effect = "Deny"
    Action = "s3:PutObject"
    Resource = "${aws_s3_bucket.data.arn}/*"
    Condition = {
      StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" }
    }
  }
]
```

## Module Versioning

```hcl
# BAD — unpinned, pulls breaking changes on next init
module "vpc" { source = "terraform-aws-modules/vpc/aws" }  # ❌

# GOOD
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"   # Allows 5.x, blocks 6.0
}
```

## Input Validation

```hcl
variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be dev, staging, or prod."
  }
}

variable "cidr_block" {
  type = string
  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}
```

## Drift Detection

```bash
terraform plan      # Shows drift (infra changed outside TF)
terraform refresh   # Sync local state with actual cloud state
```

## Pre-Apply Checklist

- [ ] No hardcoded secrets in any `.tf` file
- [ ] All sensitive vars marked `sensitive = true`
- [ ] State backend encrypted with KMS
- [ ] IAM policies use specific actions + resources (no `*`)
- [ ] Module versions pinned (`version = "~> x.y"`)
- [ ] All resources tagged (Environment, Owner, CostCenter)
- [ ] `tfsec` + `checkov` passed in CI
- [ ] `terraform plan` reviewed for expected changes ONLY

## Rules

- ALWAYS `sensitive = true` on secret variables
- ALWAYS encrypt state backend (S3+KMS or Terraform Cloud)
- ALWAYS pin module versions (`version = "~> x.y"`)
- NEVER commit `.tfvars` with secrets (use `example.tfvars` template)
- NEVER `terraform destroy -auto-approve` — human confirmation required
- NEVER `default = "<secret>"` in variable blocks
- Run `tfsec` + `checkov` in CI before every plan
