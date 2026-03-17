---
name: docker-security
description: Container hardening, image security, and Docker best practices. Use when building, scanning, or securing containers and images.
paths: ["**/Dockerfile*", "**/docker-compose*", "**/.dockerignore", "**/docker-compose.yml", "**/docker-compose.yaml", "**/docker-bake*"]
---

# Docker Security

## Image Build Security

1. **Lint before build**: `hadolint Dockerfile`
2. **Scan immediately**: `trivy image <org>/<app>:<tag>` — catch CVEs before registry push
3. **Generate SBOM**: `syft <org>/<app>:<tag> -o spdx-json > sbom.spdx.json`
4. **Check layers**: `dive <org>/<app>:<tag>` — identify bloat, leaked files

## Image Hardening Checklist

- **Base image**: Use distroless or Chainguard — `gcr.io/distroless/base:nonroot` or `cgr.io/chainguard/base:latest`
- **No root**: `RUN useradd -m -u 1000 app && chown -R app:app /app` → `USER app`
- **Read-only FS**: `docker run --read-only --tmpfs /tmp --tmpfs /run <image>`
- **Drop caps**: `docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE <image>`
- **No secrets in layers**: Use `RUN --mount=type=secret` (Docker 18.04+)

## Docker Compose Security

```yaml
services:
  app:
    image: <image>:<pinned-tag>   # Never use latest in prod
    user: "1000:1000"
    read_only: true
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    tmpfs: [/tmp, /run]
    security_opt:
      - no-new-privileges:true
    networks:
      - internal

networks:
  internal:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"  # Block inter-container comms
```

## Secret Scanning

```bash
trivy image --scan-secrets <org>/<app>:<tag>   # Leaked secrets in layers
grype <org>/<app>:<tag>                        # CVE + secret detection
gitleaks detect .                              # Pre-push secret scan
```

## Registry Hardening

```bash
cosign sign <image>:<tag>                         # Sign (requires COSIGN_KEY env)
cosign verify --key cosign.pub <image>:<tag>      # Verify on pull
trivy image --severity HIGH,CRITICAL --exit-code 1 <image>:<tag>  # Gate in CI
crane manifest <image>:<tag> | jq .               # Inspect remote manifest
cosign tree <image>:<tag>                         # Check provenance + attestations
```

## Runtime Security

```bash
docker run --security-opt apparmor=docker-default <image>   # AppArmor profile
docker run -m 512m --cpus=1 <image>                          # Limit resources (DoS protection)
docker run -v /data:/data:ro <image>                         # Read-only volume mounts
docker run --security-opt no-new-privileges:true <image>     # Block privilege escalation
# Verify storage driver: docker info | grep "Storage Driver" (should be overlay2)
```

## Multi-Stage Build (Minimal Attack Surface)

```dockerfile
# Stage 1: Build
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN go build -o myapp .

# Stage 2: Runtime (distroless — no shell, no package manager)
FROM gcr.io/distroless/base:nonroot
COPY --from=builder /app/myapp /myapp
USER nonroot
ENTRYPOINT ["/myapp"]
```

## Rules

- NEVER pin `latest` tag in deployments — use commit SHA or semver
- NEVER copy entire filesystem — COPY selectively + maintain `.dockerignore`
- NEVER log secrets to stdout/stderr (ends up in container logs)
- ALWAYS group `apt-get install && apt-get clean` in single RUN layer
- ALWAYS use multi-stage builds to minimize final image size
- ALWAYS scan images in CI before push (`trivy --exit-code 1` on CRITICAL)
- NEVER run containers with `--privileged` unless absolutely necessary
