# Container Management Guide for Endo API

## Overview

The Endo API project now uses a simple, portable container approach based on standard Docker/Podman images. DevEnv remains for the local developer shell only. Containers are built and run via the `manage docker-*` helpers.

## Architecture

### Container Strategy

- Standard Dockerfiles in `container/` produce two images:
  - `endo-api:dev` for development
  - `endo-api:prod` for production
- Runtime configuration is provided via environment variables. No secrets are baked into images. No volumes are required for credentials.

### Secrets and Configuration (Kubernetes-friendly)

- Preferred: Environment variables only (mounted from Secrets/ConfigMaps)
- Supported DB options (priority):
  1. `DATABASE_URL` (e.g., `postgresql://USER:PASSWORD@HOST:5432/DB`)
  2. Explicit `DB_ENGINE`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`
- Required for production: `DJANGO_SECRET_KEY`

Example Kubernetes env:
```yaml
env:
  - name: DJANGO_ENV
    value: "production"
  - name: DJANGO_SECRET_KEY
    valueFrom:
      secretKeyRef: { name: endo-api, key: django-secret-key }
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef: { name: endo-api-db, key: url }
  - name: DJANGO_ALLOWED_HOSTS
    value: "api.example.com,localhost"
  - name: DJANGO_DEBUG
    value: "false"
```

## Management Commands

```bash
# Build
manage docker-dev-build
manage docker-prod-build

# Run (env-first)
manage docker-dev-run
DJANGO_SECRET_KEY=... DATABASE_URL=... manage docker-prod-run

# Logs
manage docker-logs [dev|prod]

# Stop/Clean
manage docker-stop
manage docker-clean
```

## Volumes

- No credentials via volumes are required. For persistence:
  - `./data -> /app/data`
  - `./staticfiles -> /app/staticfiles`

## Troubleshooting

- Error "DJANGO_SECRET_KEY must be set": provide it via env.
- Error "Database configuration missing": set `DATABASE_URL` or `DB_*` variables.
- Port used: change `DJANGO_PORT` when running.

---

Last updated: September 2025
