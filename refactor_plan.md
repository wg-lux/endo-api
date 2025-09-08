High-level code review

Architecture

Unified management via DevEnv is solid. The single entrypoint script (devenv/management.nix: manage) and modular tasks/scripts/processes are coherent.
Centralized configuration in app_config.nix + derived env in vars.nix is good.
Mode switching is consistent through .mode + ENDO_API_MODE, but handling is duplicated (see DRY section).
Strengths

Container workflows are well-integrated (devenv containers with copy/run to Docker/Podman).
Documentation is extensive and generally aligned with code.
Secrets are not baked into Nix; DB_CONFIG_FILE + conf/db_pwd pattern is correct for production.
Issues and risks

Inaccurate docs: README previously referenced manage logs and scripts that don’t exist (postgres-check.py, environment.py --clean/--status). Fixed in README.
Missing env in containers: settings_prod.py requires DB_CONFIG_FILE; previously not guaranteed in container run args. Fixed by injecting -e DB_CONFIG_FILE in container runtime args.
DRY violations: server startup logic duplicated between scripts.nix (serverStartup) and management.nix (run-server). Environment bootstrap/deploy pipeline also partly duplicated.
Mixed env sources: DJANGO_SETTINGS_MODULE is set in several places (environment.py, Dockerfile.dev, entrypoints), which can drift. ENDO_API_MODE is set in .env, .mode, and devenv.nix. Clear precedence is needed.
DATABASE_* variables in environment.nix are unused by Django in prod (prod uses DB_CONFIG_FILE via endoreg_db), which can confuse operators.
DRY analysis

Server run logic duplicated

- devenv/scripts.nix: run-server and run-server-container with serverStartup function
- devenv/management.nix: scripts.run-server with similar flow
- Risk: behavior diverges over time (e.g., production migrate/collectstatic vs development runserver).
Environment setup duplicated

- devenv/scripts.nix: env-pipe calls manage setup; env-export loads .env
- devenv/management.nix: tasks.env:setup runs make_conf.py + setup.py and calls env:setup-cuda
- docker-entrypoint.sh also triggers env:setup-cuda; duplication but contextually OK.
Mode handling duplicated

- .mode file (manage dev/prod), ENDO_API_MODE from .env, and ENDO_API_MODE set by Nix in devenv.nix and environment.nix. Similar logic appears in multiple places.
Configuration surface duplication

- Dockerfile.dev injects defaults (ENDO_API_MODE, DJANGO_SETTINGS_MODULE), entrypoints set defaults again, and environment.py set them too.
Environment variables: audit and recommendations

Current sources

- Nix export defaults via devenv.nix + environment.nix + vars.nix (e.g., DB_CONFIG_FILE, CONF_DIR, DATA_DIR, DJANGO_*).
- .env managed by setup.py and environment.py (mode-specific).
- Container runtime args (now include DB_CONFIG_FILE; previously missing).
- Entry points (docker-entrypoint*.sh) set fallbacks and create .env in dev container if missing.
- Django settings: prod requires DB_CONFIG_FILE; dev uses sqlite regardless of DATABASE_* env.
Precedence (recommended and mostly observed)

- OS environment > .env > Nix defaults (doc this in README; implied by env-export + shell).
- Single source for DB settings in prod: DB_CONFIG_FILE (matches settings_prod.py).
Gaps fixed

- Added DB_CONFIG_FILE to container runtime args in management.nix so prod containers can always load conf/db.yaml.
- README now shows the correct troubleshooting commands and avoids non-existent scripts/commands.
Further improvements

- Fail hard in production if DJANGO_SECRET_KEY is missing (currently warns and uses a temp key in docker-entrypoint-prod.sh). Consider strict mode for first publication.
- Remove DATABASE_* from environment.nix (or mark clearly as non-authoritative in prod) to avoid confusion; prod uses DB_CONFIG_FILE exclusively.

---

Phase 2: DRY server startup — IMPLEMENTED

What changed

- Added unified server script: scripts/core/server-run.sh
  - Detects mode (.mode > ENDO_API_MODE > development)
  - Ensures .env/conf exist (runs setup pipeline if needed)
  - Honors DJANGO_HOST/DJANGO_PORT/DJANGO_MODULE at runtime (env-first, no rebuilds)
  - Prod: migrate → load_base_db_data (if available) → collectstatic → daphne (fallback to runserver)
  - Dev: migrate → runserver
- Delegated run-server to the unified script:
  - devenv/scripts.nix: run-server and run-server-container now execute bash scripts/core/server-run.sh
  - devenv/management.nix: scripts.run-server and scripts.run-server-container now execute the same script
- Kept container entrypoints untouched for now (next iteration can switch to server-run.sh for full DRY)

Why this helps

- One source of truth for startup across dev, local Docker, future Kubernetes exec patterns
- Runtime env controls host/port/mode without image rebuilds
- Aligns with deployment plan: build once; configure via env (Kubernetes: ConfigMaps/Secrets; Docker: -e flags)

How to test

- Dev shell:
  - manage dev && devenv up
  - Override port without rebuild: DJANGO_PORT=8120 run-server
- Docker (local):
  - manage dev && manage build && manage copy && manage run
  - Override host/port: docker run -e DJANGO_HOST=0.0.0.0 -e DJANGO_PORT=9000 …
- Prod container:
  - manage prod && manage build && manage copy && manage run
  - Ensure DB_CONFIG_FILE is honored (now injected) and app starts

Kubernetes alignment

- Supply variables via env (Deployment) and mount conf/ as a volume:
  - env: ENDO_API_MODE=production, DJANGO_SECRET_KEY (Secret), DB_CONFIG_FILE=/app/conf/db.yaml, DJANGO_HOST=0.0.0.0, DJANGO_PORT=8118
  - volumes: mount conf/ (ConfigMap + Secret for db.yaml and db_pwd) at /app/conf
- No rebuild required for host/port/urls/keys changes

Next steps (Phase 3)

- Make .mode authoritative locally; keep ENDO_API_MODE as override for CI/containers
- Update environment.py to write/read .mode and avoid conflicts
- Optionally switch docker-entrypoint*.sh to call scripts/core/server-run.sh for full DRY
- Consider strict prod secret policy (fail when DJANGO_SECRET_KEY missing)
