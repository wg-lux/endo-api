# Endo API Cleanup Analysis Report
==================================================
Generated: 2025-08-31 19:27:23
Total items found: 29

## DEPRECATED (19 items)

### LOW RISK (13 items)

**docker-compose.yml**
- Type: file
- Reason: Explicitly marked as deprecated in favor of docker-manager.sh generated configs
- Replacement: Use docker-manager.sh to generate up-to-date configurations
- Backup needed: Yes

**docker-compose.prod.yml**
- Type: file
- Reason: Explicitly marked as deprecated in favor of docker-manager.sh generated configs
- Replacement: Use docker-manager.sh to generate up-to-date configurations
- Backup needed: Yes

**scripts/env_manager.py**
- Type: file
- Reason: Replaced by unified management: manage setup command
- Replacement: manage setup command
- Backup needed: No

**scripts/config_manager.py**
- Type: file
- Reason: Replaced by unified management: manage setup command
- Replacement: manage setup command
- Backup needed: No

**scripts/setup_project.py**
- Type: file
- Reason: Replaced by unified management: manage setup command
- Replacement: manage setup command
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 63: deprecatedCommand = newCommand: oldCommand: {
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 65: echo "⚠️  DEPRECATED: Use '${newCommand}' instead. This command will be removed in a future version."
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 74: (deprecatedCommand "run-server" "run-dev-server") //
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 75: (deprecatedCommand "run-server" "run-prod-server") //
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 76: (deprecatedCommand "run-server-container" "run-dev-server-container") //
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 77: (deprecatedCommand "run-server-container" "run-prod-server-container") //
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 78: (deprecatedCommand "start-services" "dev-up")
- Replacement: Check surrounding context for new implementation
- Backup needed: No

**devenv/scripts.nix**
- Type: code_pattern
- Reason: Deprecated code pattern on line 169: echo "⚠️  DEPRECATED: Use 'start-services' instead. This command will be removed in a future version."
- Replacement: Check surrounding context for new implementation
- Backup needed: No

### MEDIUM RISK (6 items)

**docker-manager.sh**
- Type: file
- Reason: Replaced by unified management system: manage build/run/stop/clean commands
- Replacement: manage build/run/stop/clean commands
- Backup needed: No

**container-dev.sh**
- Type: file
- Reason: Replaced by unified management system: manage dev && manage build && manage run
- Replacement: manage dev && manage build && manage run
- Backup needed: No

**deploy-prod.sh**
- Type: file
- Reason: Replaced by unified management system: manage prod && manage deploy
- Replacement: manage prod && manage deploy
- Backup needed: No

**switch-mode.sh**
- Type: file
- Reason: Replaced by unified management system: manage dev/prod commands
- Replacement: manage dev/prod commands
- Backup needed: No

**config-manager.sh**
- Type: file
- Reason: Replaced by unified management system: manage setup command
- Replacement: manage setup command
- Backup needed: No

**docker-cleanup.sh**
- Type: file
- Reason: Replaced by unified management system: docker system prune or manage clean
- Replacement: docker system prune or manage clean
- Backup needed: No

## POTENTIALLY_UNUSED (2 items)

### HIGH RISK (2 items)

**Dockerfile.dev**
- Type: file
- Reason: DevEnv native containers may replace traditional Dockerfiles
- Replacement: DevEnv containers in devenv/containers.nix
- Backup needed: Yes

**Dockerfile.prod**
- Type: file
- Reason: DevEnv native containers may replace traditional Dockerfiles
- Replacement: DevEnv containers in devenv/containers.nix
- Backup needed: Yes

## OUTDATED (6 items)

### MEDIUM RISK (6 items)

**test-containers.sh**
- Type: file
- Reason: Test script references legacy management commands
- Replacement: Update to use 'manage' commands
- Backup needed: Yes

**test-clean-implementation.sh**
- Type: file
- Reason: Test script references legacy management commands
- Replacement: Update to use 'manage' commands
- Backup needed: Yes

**test-container-functionality.sh**
- Type: file
- Reason: Test script references legacy management commands
- Replacement: Update to use 'manage' commands
- Backup needed: Yes

**test-containers.sh**
- Type: file
- Reason: Test script references legacy management commands
- Replacement: Update to use 'manage' commands
- Backup needed: Yes

**test-clean-implementation.sh**
- Type: file
- Reason: Test script references legacy management commands
- Replacement: Update to use 'manage' commands
- Backup needed: Yes

**test-container-functionality.sh**
- Type: file
- Reason: Test script references legacy management commands
- Replacement: Update to use 'manage' commands
- Backup needed: Yes

## BACKUP (1 items)

### LOW RISK (1 items)

**legacy_scripts_backup**
- Type: directory
- Reason: Backup directory with 9 files from migration
- Replacement: Can be removed after verifying unified system works
- Backup needed: No

## TEMPORARY (1 items)

### LOW RISK (1 items)

**legacy_aliases.sh**
- Type: file
- Reason: Temporary compatibility file for migration period
- Replacement: Remove after full migration to unified commands
- Backup needed: No
