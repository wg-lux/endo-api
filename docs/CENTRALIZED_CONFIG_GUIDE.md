# Centralized Configuration System

This document provides a complete guide to the centralized configuration system implemented for the EndoReg API project.

## Quick Start

### 1. View Current Configuration
```bash
./config-manager.sh show-config
```

### 2. Change Common Settings
```bash
# Change server port
./config-manager.sh set-port 8080

# Change server host  
./config-manager.sh set-host 0.0.0.0

# Change Django module name
./config-manager.sh set-module my_api

# Change application name (affects container names)
./config-manager.sh set-app-name my-app
```

### 3. Apply Changes
```bash
direnv reload
devenv shell
```

## Architecture

The centralized configuration system provides a single source of truth for all application settings through `app_config.nix`.

### Configuration Flow
```
app_config.nix → devenv.nix → Environment Variables → All Components
      ↑               ↑              ↑                    ↑
  Single source   Main config   Runtime values   Scripts, containers,
   of truth      orchestrator                    services, etc.
```

## Configuration File Structure

### `app_config.nix`
The main configuration file contains all customizable application settings:

```nix
{
  # Core Application Identity
  app = {
    name = "endo-api";               # Application name (affects container names)
    djangoModule = "endo_api";       # Django project module name
    version = "1.0.0";
  };

  # Server Configuration  
  server = {
    host = "localhost";              # Host binding for development
    port = "8118";                   # Server port
    protocol = "http";               # http or https
    containerHost = "0.0.0.0";      # Host binding for containers
  };

  # Database Configuration
  database = {
    dev = {
      engine = "django.db.backends.sqlite3";
      name = "./data/db.sqlite3";
    };
    prod = {
      engine = "django.db.backends.postgresql";
      name = "endoregDbLocal";
      host = "localhost";  
      port = "5432";
      user = "endoregDbLocal";
      passwordFile = "conf/db_pwd";
    };
  };

  # Directory Structure
  paths = {
    data = "./data";
    conf = "./conf";
    confTemplate = "./conf_template";
    staticFiles = "./staticfiles";
    # ... more paths
  };

  # Service Dependencies
  services = {
    postgres = {
      version = "15-alpine";
      port = "5432";
    };
    redis = {
      version = "7-alpine";  
      port = "6379";
    };
  };
}
```

## Components Using Centralized Configuration

### 1. DevEnv Configuration (`devenv.nix`)
- Imports `app_config.nix`
- Sets environment variables based on config values
- Passes configuration to all modular components

### 2. Container Configuration (`devenv/containers.nix`)
- Uses `appConfig.app.name` for container naming
- Uses `appConfig.server.port` for port mapping
- Uses `appConfig.server.containerHost` for host binding

### 3. Scripts (`devenv/scripts.nix`)
- Server startup commands use centralized host/port
- Container operations use dynamic names from config
- All scripts reference centralized configuration

### 4. Environment Variables (`devenv/environment.nix`)
- Generates environment variables from centralized config
- Mode-aware database configuration
- Path variables from centralized paths

### 5. Environment Manager (`scripts/env_manager.py`)
- Reads `app_config.nix` using nix-instantiate
- Generates `.env` files with centralized values
- Supports force regeneration with `--force` flag

## Usage Examples

### Changing Server Port

**Old Way** (before centralized config):
- Edit `devenv.nix`
- Edit `devenv/scripts.nix`
- Edit `devenv/containers.nix`
- Edit `docker-compose.yml`
- Edit environment files
- Update documentation

**New Way** (with centralized config):
```bash
./config-manager.sh set-port 8080
direnv reload
```

### Changing Django Module Name

**Old Way**: Multiple file edits, risk of inconsistency

**New Way**:
```bash
./config-manager.sh set-module my_api
# Then rename the actual Django directory and update imports
direnv reload
```

### Changing Application Name

**Old Way**: Complex search and replace across many files

**New Way**:
```bash
./config-manager.sh set-app-name my-app
# Rebuild containers to use new names
container-build-dev
```

## Container Management

The system includes DRY container configuration that automatically uses your centralized settings:

### Build Containers
```bash
# Build development container
./docker-manager.sh build-dev

# Build production container  
./docker-manager.sh build-prod

# Build both
./docker-manager.sh build-all
```

### Run Containers
```bash
# Run development container
./docker-manager.sh run-dev

# Run production container
./docker-manager.sh run-prod
```

### Test Containers
```bash
# Test development container build and runtime
./docker-manager.sh test-dev

# Test production container build and runtime
./docker-manager.sh test-prod

# Test both containers
./docker-manager.sh test-all
```

### Generate Docker Compose
The system can generate up-to-date Docker Compose files using your centralized configuration:

```bash
# Generate development compose file
./docker-manager.sh generate-compose-dev

# Generate production compose file
./docker-manager.sh generate-compose-prod

# Generate both
./docker-manager.sh generate-compose-all
```

Generated files include:
- `docker-compose.dev.generated.yml` - Development with hot reload
- `docker-compose.prod.generated.yml` - Production with PostgreSQL and Redis

### Container Configuration

All container settings are automatically pulled from `app_config.nix`:

```nix
containers = {
  devImage = "endo-api-dev";
  prodImage = "endo-api-prod";
  resources = {
    memory = "2g";
    cpus = "2.0";
  };
};
```

When you change the server port or Django module name in the config, all containers automatically use the new values.

## Environment Variable Precedence

The system uses a flexible precedence hierarchy:

1. **Environment Variables** (highest priority)
2. **`.env` file values**
3. **Centralized config (`app_config.nix`)**
4. **Default fallbacks** (lowest priority)

This allows for:
- **Development**: Override with `.env` file
- **Production**: Override with environment variables
- **Default**: Use centralized configuration

## Testing

### Smoke Tests
Run quick validation tests:
```bash
python3 tests/smoke_tests.py
```

### Database Connectivity Tests
Test PostgreSQL connection and Django compatibility:
```bash
python3 tests/test_database_connectivity.py
```

These tests verify:
- **PostgreSQL Connection**: Can connect using configured credentials
- **Database Tables**: Essential Django tables exist
- **Migration Status**: Shows unapplied migrations if any
- **Database Permissions**: User has required CREATE, INSERT, SELECT, UPDATE, DELETE permissions

### Container Testing
Test container builds and runtime:
```bash
./test-containers.sh
```

This validates:
- **Docker Availability**: Docker daemon is running
- **Dockerfile Syntax**: Both dev and prod Dockerfiles are valid
- **Configuration Consistency**: Centralized config can be read
- **Container Builds**: Both development and production images build successfully
- **Container Runtime**: Containers start and respond correctly
- **Compose Generation**: Docker Compose files can be generated

### Comprehensive Tests
Run full test suite:
```bash
python3 tests/test_centralized_config.py
```

## Configuration Manager Script

### `config-manager.sh`

A user-friendly script for common configuration changes:

```bash
# Show help
./config-manager.sh help

# Show current configuration
./config-manager.sh show-config

# Change settings
./config-manager.sh set-port <port>
./config-manager.sh set-host <host>
./config-manager.sh set-module <name>
./config-manager.sh set-app-name <name>
```

### Script Features
- **Input validation**: Checks for required parameters
- **Safe updates**: Uses sed for precise changes
- **Clear instructions**: Shows next steps after changes
- **Error handling**: Provides helpful error messages

## Environment Manager

### `scripts/env_manager.py`

Enhanced environment management with centralized configuration support:

```bash
# Generate environment file from config
python3 scripts/env_manager.py

# Force regeneration (ignores existing file)
python3 scripts/env_manager.py --force

# Specify mode
python3 scripts/env_manager.py --mode production
```

### Features
- **Nix Integration**: Reads configuration using `nix-instantiate`
- **Mode Awareness**: Different settings for dev/prod/central
- **Smart Merging**: Preserves existing secrets and custom values
- **Force Update**: Option to completely regenerate configuration

## Benefits

### 1. Single Source of Truth
- All configuration in one place (`app_config.nix`)
- No more scattered settings across multiple files
- Consistent values across all components

### 2. Easy Maintenance
- Change port with one command
- No risk of missing files during updates
- Clear documentation of all settings

### 3. Reduced Errors
- No more inconsistent port/host configurations
- Automated propagation of changes
- Validation through tests

### 4. Better Developer Experience
- Simple command-line interface
- Clear instructions for common tasks
- Self-documenting configuration file

### 5. Scalability
- Easy to add new configuration options
- Modular structure supports growth
- Clean separation of concerns

## Migration from Legacy Configuration

### Before (Legacy System)
- Settings scattered across 20+ files
- Manual coordination required for changes
- Risk of inconsistency and errors
- Complex deployment process

### After (Centralized System)
- Single configuration file
- Automated propagation
- Consistent values guaranteed
- Simple change process

## Troubleshooting

### Configuration Not Applied
1. Check if configuration file has valid Nix syntax:
   ```bash
   nix-instantiate --parse app_config.nix
   ```

2. Reload environment:
   ```bash
   direnv reload
   devenv shell
   ```

3. Force regenerate environment file:
   ```bash
   python3 scripts/env_manager.py --force
   ```

### Container Issues After Config Changes
1. Rebuild containers with new configuration:
   ```bash
   container-build-dev
   container-build-prod
   ```

2. Check that container names match configuration:
   ```bash
   ./config-manager.sh show-config
   docker ps -a
   ```

### DevEnv Build Errors
1. Validate Nix syntax:
   ```bash
   nix-instantiate --eval devenv.nix
   ```

2. Check configuration accessibility:
   ```bash
   python3 tests/smoke_tests.py
   ```

## Best Practices

### 1. Always Test Changes
```bash
# After configuration changes
python3 tests/smoke_tests.py
```

### 2. Use Version Control
- Commit configuration changes
- Tag releases with configuration state
- Document breaking changes

### 3. Environment-Specific Overrides
- Use `.env` for development customizations
- Use environment variables for production
- Keep centralized config for defaults

### 4. Regular Validation
- Run smoke tests in CI/CD
- Validate after environment updates
- Check consistency across deployments

## Future Enhancements

### Planned Features
- **Web UI**: Browser-based configuration management
- **Validation**: Schema validation for configuration values
- **Templates**: Configuration templates for different deployment scenarios
- **Import/Export**: Configuration backup and restore functionality

### Extensibility
The system is designed to be easily extended:
- Add new configuration sections to `app_config.nix`
- Update `config-manager.sh` for new settings
- Add validation to smoke tests
- Document new options

## Related Documentation

- [`NATIVE_DEVENV_CONTAINERS_GUIDE.md`](./NATIVE_DEVENV_CONTAINERS_GUIDE.md) - Complete DevEnv container guide
- [`scripts/env_manager.py`](./scripts/env_manager.py) - Environment management implementation
- [`devenv.nix`](./devenv.nix) - Main DevEnv configuration
- [`tests/`](./tests/) - Test suite documentation

---

For questions or issues with the centralized configuration system, please refer to the test suite or create an issue with detailed reproduction steps.
