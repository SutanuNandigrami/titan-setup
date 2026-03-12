---
paths: ["**/Dockerfile*", "**/docker-compose*", "**/compose.yaml", "**/compose.yml"]
---
# Docker Rules
- Lint with `hadolint` before building
- Scan images with `trivy image` before pushing
- Generate SBOM with `syft` and scan with `grype`
- Use multi-stage builds to minimize image size
- Pin base image versions — no `:latest` in production
- Use `dive` to analyze layer efficiency
- Run as non-root user
- Verify signatures with `cosign verify` when pulling third-party images
