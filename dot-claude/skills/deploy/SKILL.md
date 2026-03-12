---
description: Deploy applications — auto-detect provider from project files, run the right deploy commands
triggers:
  - deploy
  - ship to production
  - push to prod
  - release
  - deploy to vercel
  - deploy to docker
  - terraform apply
  - helm upgrade
paths: ["**/Dockerfile*", "**/docker-compose*", "**/compose.y*ml", "**/*deploy*", "**/*.helm", "**/Chart.yaml", "**/fly.toml", "**/vercel.json"]
---

# Deploy Skill

Auto-detect deployment target from project files and run the correct commands.

## Provider Detection

| File/Dir | Provider | Deploy Command |
|----------|----------|---------------|
| `vercel.json` or `.vercel/` | Vercel | `vercel --prod` |
| `Dockerfile` + no k8s | Docker | `docker compose up -d --build` |
| `docker-compose.yml` | Docker Compose | `docker compose up -d --build` |
| `fly.toml` | Fly.io | `fly deploy` |
| `terraform/` or `*.tf` | Terraform | `terraform plan && terraform apply` |
| `k8s/` or `helm/` | Kubernetes | `helm upgrade` or `kubectl apply` |
| `serverless.yml` | Serverless | `serverless deploy` |
| `netlify.toml` | Netlify | `netlify deploy --prod` |
| `railway.json` | Railway | `railway up` |
| `Procfile` | Heroku-like | Platform-specific |

## Pre-Deploy Checklist
1. Run tests: detect from `_workspace.json` or auto-detect
2. Run linter: `ruff check .` / `bun lint` / `cargo clippy`
3. Scan secrets: `gitleaks detect --verbose`
4. Scan vulnerabilities: `trivy fs .` or `osv-scanner -r .`
5. Build: detect from project type
6. Deploy: run provider command

## Patterns

### Vercel
```bash
vercel --prod
```

### Docker + Registry
```bash
docker build -t registry.example.com/app:latest .
trivy image registry.example.com/app:latest
docker push registry.example.com/app:latest
```

### Terraform
```bash
cd terraform/
terraform init
terraform plan -out=tfplan
# Show plan and ask for confirmation
terraform apply tfplan
```

### Kubernetes (Helm)
```bash
helm upgrade --install app ./helm/app \
  --namespace production \
  --values helm/app/values-prod.yaml \
  --wait --timeout 5m
kubectl rollout status deployment/app -n production
```

### Cloudflare Tunnel (expose local)
```bash
cloudflared tunnel --url http://localhost:3000
```

## Rules
1. ALWAYS run pre-deploy checklist before deploying.
2. ALWAYS show the plan/diff and ask for confirmation before applying.
3. Never deploy directly to production without user confirmation.
4. Use `_workspace.json` deploy command if available.
5. For Terraform, always `plan` before `apply`.
6. Tag releases: `git tag v$(date +%Y%m%d.%H%M)` after successful deploy.
