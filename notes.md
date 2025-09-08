Completed Phase 1 and 2.

What changed

Removed DevEnv container framework from runtime:
Dropped all container:* tasks from management.nix.
Added native Docker/Podman helpers: docker-dev-build/run, docker-prod-build/run, docker-logs, docker-stop, docker-clean.
Kept local dev via run-server (uses server-run.sh).
Updated docs:
README.md: new docker-* commands and workflows.
CONTAINER_MANAGEMENT_GUIDE.md: rewritten for Docker/Podman.
NATIVE_DEVENV_CONTAINERS_GUIDE.md: marked deprecated.
How to use

Refresh shell: direnv reload (or reopen shell).
Dev (Podman preferred, falls back to Docker):
manage dev && manage setup
manage docker-dev-build
manage docker-dev-run
manage docker-logs dev
Prod:
ensure db.yaml exists and mountable
export DJANGO_SECRET_KEY=$(openssl rand -base64 32)
manage docker-prod-build
manage docker-prod-run
manage docker-logs prod

## Quick Checks
List: podman ps --filter name=endo-api-dev
Logs: podman logs -f endo-api-dev
Ports: podman port endo-api-dev
Exec: podman exec -it endo-api-dev bash