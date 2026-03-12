Run security scan on current project:
1. `gitleaks detect --verbose` — secrets
2. `trivy fs --severity HIGH,CRITICAL .` — filesystem vulns
3. If lockfile exists: `osv-scanner --lockfile=<detected lockfile>`
4. If Dockerfile exists: `hadolint Dockerfile`
5. If .tf files exist: `tflint` and `trivy config .`
Summarize findings by severity. Suggest fixes for critical/high. $ARGUMENTS
