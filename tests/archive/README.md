# Archived Tests

## Container Tests (Legacy)
- **File**: `test-containers-legacy.sh`
- **Archived**: 2025-01-15
- **Reason**: Tests outdated Docker architecture (docker-manager.sh, old Dockerfiles, compose generation)
- **Replacement**: Modern container validation in `scripts/core/system-validation.sh` using DevEnv containers

The legacy container tests were designed for the old Docker-based architecture and are no longer compatible with the current DevEnv-based container system.
