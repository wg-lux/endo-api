# Native DevEnv Containers Implementation Guide (Deprecated)

This document previously described the native DevEnv container workflow. The project has migrated away from DevEnv-managed containers to a simpler, more portable Docker/Podman approach.

Please refer to the updated guide:

- Container Management (Docker/Podman): docs/CONTAINER_MANAGEMENT_GUIDE.md

DevEnv remains in use for the local developer shell only (reproducible environment, tooling). All container build/run tasks are now provided via `manage docker-*` helpers implemented in `devenv/management.nix`.

Last updated: September 2025
