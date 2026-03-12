---
name: security-scan
description: Security scanning and vulnerability assessment workflows. Use when performing security audits, scanning for vulnerabilities, checking dependencies, or hardening systems.
paths: ["**/*.py", "**/*.js", "**/*.go", "**/*.sh", "**/*.ts", "**/*.rs", "**/Dockerfile*", "**/requirements*.txt", "**/package.json", "**/*.tf"]
---

# Security Scanning Workflows

## Pre-Push Security Check
Before any push to remote, run this sequence:
1. `gitleaks detect --verbose` — scan for leaked secrets
2. `trivy fs --severity HIGH,CRITICAL .` — filesystem vulnerability scan
3. `osv-scanner --lockfile=<lockfile>` — dependency vulnerability check

## Container Security
1. `trivy image <image>` — scan container image
2. `syft <image>` — generate SBOM (Software Bill of Materials)
3. `grype <image>` — scan SBOM/image for known vulnerabilities
4. `crane manifest <image>` — inspect remote image without pulling
5. `cosign verify <image>` — verify image signature
6. `dive <image>` — check image layer efficiency
7. `hadolint Dockerfile` — lint Dockerfile for best practices

## Infrastructure Security
1. `trivy config .` — scan Terraform/CloudFormation for misconfigs
2. `tflint` — lint Terraform files
3. `semgrep --config auto .` — static analysis

## Network Reconnaissance
1. `subfinder -d <domain>` — passive subdomain enumeration
2. `dnsx -l subdomains.txt -resp` — bulk DNS resolution
3. `httpx -l hosts.txt -sc -title -tech-detect` — probe for live HTTP services
4. `katana -u <url>` — crawl with JS rendering for hidden endpoints
5. `nmap -sV -sC <target>` — service version detection
6. `nuclei -u <target>` — template-based vuln scanning
7. `nikto -h <target>` — web server scanning
8. `ffuf -u <url>/FUZZ -w <wordlist>` — directory fuzzing

## Supply Chain Security
1. `syft dir:.` — generate SBOM for project directory
2. `grype sbom:./sbom.json` — scan SBOM for known CVEs
3. `grype dir:.` — scan project directly for vulnerable dependencies

## TLS & Certificate Debugging
1. `step certificate inspect <cert.pem>` — view certificate details
2. `step certificate inspect https://<domain>` — inspect remote TLS cert
3. `step certificate create` — generate self-signed certs for testing

## System Hardening
1. `lynis audit system` — full system security audit
2. Review output and address findings by severity

## Rules
- NEVER scan targets you don't own or have authorization for
- Always use `--help` before running any security tool
- Report findings clearly with severity levels
- Suggest remediations alongside findings
