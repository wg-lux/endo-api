# endo-api
Basic Django Project using EndoReg-DB

## Quick Start Guide

This project uses a modular devenv configuration that supports both development and production modes.

### Development Environment Setup

1. **Setup Environment**:
   ```bash
   direnv allow
   devenv shell
   ```

2. **Switch Modes**:
   ```bash
   # Development mode (SQLite, local services)
   ./switch-mode.sh dev
   
   # Production mode (PostgreSQL, external services)  
   ./switch-mode.sh prod
   ```

3. **Run Services**:
   ```bash
   # Unified commands that adapt to current mode
   start-services           # Start environment with services  
   run-server              # Start server (dev: SQLite, prod: PostgreSQL)
   
   # Background services only
   services-up             # Start background services
   ```

### Mode Overview

- **Development Mode**: Uses SQLite database, provides local PostgreSQL/Redis services
- **Production Mode**: Uses external PostgreSQL, expects external services

See [MODULAR_DEVENV.md](MODULAR_DEVENV.md) for detailed documentation.

## Environment Setup

### Development Environment (Local)

For local development, the application uses `.env` files for configuration:

1. **Initialize the environment**:
   ```bash
   # Enter the devenv shell
   devenv shell
   
   # Test luxnix compatibility
   test-luxnix-compatibility
   
   # Initialize configuration
   devenv task run env:init-conf
   devenv task run env:build
   ```

2. **Run the development server**:
   ```bash
   # Mode-aware server command
   run-server
   
   # Or manually (if needed):
   python manage.py runserver localhost:8118
   ```

### Containerized Environment (Recommended)

The project now supports containerized development and production environments using devenv:

1. **Quick start with containers**:
   ```bash
   # Start environment (adapts to current mode)
   start-services
   
   # Legacy commands (still work but deprecated)
   dev-up                   # Use start-services instead
   ```

2. **Individual services**:
   ```bash
   # Start specific services
   devenv up endo-api-dev postgres
   devenv up endo-api-prod nginx redis
   
   # Stop all services
   devenv down
   ```

3. **Container management**:
   ```bash
   # View logs
   devenv logs -f
   
   # Database operations
   db-shell-container
   db-backup-container
   ```

See [CONTAINER_SETUP.md](CONTAINER_SETUP.md) for detailed container usage instructions.

### Production Environment (Luxnix Managed)

When deployed on luxnix-managed machines, configuration is automatic:

- **No manual setup required** - luxnix provides `local_settings.py`
- **Database credentials** are loaded from the luxnix vault system
- **Security settings** are managed by the deployment system
- **Environment detection** is automatic

## Luxnix Compatibility

This application is designed to work seamlessly with managed machines running on custom NixOS configurations via the luxnix project. The application automatically detects luxnix environments and adapts its configuration accordingly.

### Key Features for Luxnix Integration:

- **Automatic Environment Detection**: Detects when running in a luxnix managed environment by checking for `local_settings.py`
- **Central Node Support**: Automatically configures for central nodes when `CENTRAL_NODE=true` environment variable is set
- **Settings Override**: Imports `local_settings.py` when available, allowing luxnix to override default configurations
- **Flexible Configuration**: All hardcoded values can be overridden via environment variables

### Central Node Configuration

When `CENTRAL_NODE=true` is set, the application operates as a central coordination node with additional capabilities:

#### **Central Node Implications:**

1. **Database Access**: Central nodes typically have access to the `endoregDbCentral` database instead of local databases
2. **Network Topology**: Central nodes are configured to communicate with local nodes across the network
3. **CORS Settings**: Automatically configured to allow cross-origin requests from local nodes
4. **Additional Endpoints**: May have access to coordination and management endpoints not available on local nodes
5. **Settings Module**: Uses `endo_api.settings_central` instead of `endo_api.settings_prod`

#### **Central Node Responsibilities:**

- **Data Aggregation**: Collects and processes data from local nodes
- **Coordination**: Manages distributed operations across the network
- **Authentication**: May serve as authentication provider for local nodes
- **Backup/Sync**: Handles data synchronization and backup operations

#### **Environment Variables for Central Nodes:**

```bash
CENTRAL_NODE=true
DJANGO_SETTINGS_MODULE=endo_api.settings_central
IS_CENTRAL_NODE=true
CENTRAL_NODES=["s-04"]  # List of central node identifiers
LOCAL_NODES=["gs-01", "gs-02", "gc-05", "gc-06", "gc-10"]  # Managed local nodes
```

### Environment Variables Reference:

The application respects the following environment variables for luxnix compatibility:

#### **Core Configuration:**
- `CENTRAL_NODE`: Set to "true" for central node configuration
- `DJANGO_HOST`: Server host (default: localhost)
- `DJANGO_PORT`: Server port (default: 8118)  
- `DJANGO_DEBUG`: Enable/disable debug mode
- `DJANGO_SECRET_KEY`: Django secret key (auto-generated if not provided)
- `DJANGO_ALLOWED_HOSTS`: Comma-separated list of allowed hosts

#### **Directory Configuration:**
- `DATA_DIR` / `STORAGE_DIR`: Data storage directory
- `CONF_DIR`: Configuration directory
- `CONF_TEMPLATE_DIR`: Template configuration directory
- `WORKING_DIR`: Application working directory

#### **Database Configuration:**
- `DB_CONFIG_FILE`: Database configuration file path
- `DB_PWD_FILE`: Database password file path

#### **Django Settings Modules:**
- `DJANGO_SETTINGS_MODULE_DEVELOPMENT`: Development settings module
- `DJANGO_SETTINGS_MODULE_PRODUCTION`: Production settings module  
- `DJANGO_SETTINGS_MODULE_CENTRAL`: Central node settings module

#### **Advanced Configuration:**
- `BASE_URL`: Full base URL for the application
- `HTTP_PROTOCOL`: Protocol (http/https)
- `LX_MAINTENANCE_PASSWORD_FILE`: Maintenance password file path

### Development vs Production vs Central Node:

| Feature | Development | Production | Central Node |
|---------|-------------|------------|--------------|
| Settings Module | `settings_dev` | `settings_prod` | `settings_central` |
| Configuration Source | `.env` file | `local_settings.py` | `local_settings.py` |
| Database | SQLite (dev) | PostgreSQL | PostgreSQL (Central DB) |
| Debug Mode | Enabled | Disabled | Disabled |
| CORS | Permissive | Restricted | Cross-node enabled |
| Network Access | Local only | Node-specific | Multi-node |
| Secret Management | Local/Manual | Luxnix Vault | Luxnix Vault |

### Luxnix Deployment Process:

When deployed via luxnix, the following happens automatically:

1. **Configuration Generation**: `local_settings.py` is created with environment-specific settings
2. **Database Setup**: PostgreSQL credentials are loaded from the luxnix vault system
3. **Security Configuration**: SSL certificates, CORS settings, and security headers are configured
4. **Service Management**: Systemd service `endo-api-boot.service` manages the application lifecycle
5. **Environment Detection**: Application automatically detects luxnix environment and skips local config generation

#### **Available Scripts and Commands:**

```bash
# Development
run-dev-server          # Start development server (local)
run-dev-server-container # Start development server (container-ready)
set-dev-settings        # Configure development settings

# Production  
run-prod-server         # Start production server (local)
run-prod-server-container # Start production server (container-ready)
set-prod-settings       # Configure production settings
set-central-settings    # Configure central node settings

# Container Management
dev-up                  # Start development container stack
prod-up                 # Start production container stack  
full-stack-up          # Start all containerized services
stack-down             # Stop all containerized services
stack-logs             # View logs from all services

container-dev-up       # Build and run development container
container-prod-up      # Build and run production container
container-stop         # Stop running containers
container-clean        # Clean up containers and images

# Database Management (Containers)
db-shell-container     # Access database shell in container
db-backup-container    # Create database backup
db-restore-container   # Restore database from backup

# Environment Management
env-pipe               # Full environment setup pipeline
env-init-conf          # Initialize configuration files
env-build              # Build .env file from templates
env-export             # Export environment variables

# Database Management (Local)
ensure-psql            # Ensure PostgreSQL is configured
deploy-migrate         # Run database migrations
deploy-load-base-db-data  # Load initial database data
deploy-collectstatic   # Collect static files

# Testing and Diagnostics
test-luxnix-compatibility  # Test luxnix integration
gpu-check             # Check GPU availability
```

## Troubleshooting

### Common Issues:

1. **Environment Variables Not Loading**:
   ```bash
   # Check .env file syntax
   cat .env
   # Reload environment
   direnv reload
   ```

2. **Database Connection Issues**:
   ```bash
   # Verify database configuration
   python manage.py check
   # Run PostgreSQL setup
   ensure-psql
   ```

3. **Luxnix Integration Problems**:
   ```bash
   # Test compatibility
   test-luxnix-compatibility
   # Check if local_settings.py exists
   ls -la local_settings.py
   ```

4. **Service Issues (Luxnix Deployment)**:
   ```bash
   # Check service logs
   sudo journalctl -u endo-api-boot.service -f
   # Restart service
   sudo systemctl restart endo-api-boot.service
   ```


## Development Setup

### Prerequisites
- NixOS with devenv installed
- Git with submodule support
- Access to luxnix repository (for managed deployments)

### Quick Start

1. **Clone and Initialize**:
   ```bash
   git clone <repository-url>
   cd endo-api
   git submodule init
   git submodule update --remote --recursive
   ```

2. **Enter Development Environment**:
   ```bash
   # This will automatically:
   # - Set up Python environment with uv
   # - Install dependencies
   # - Configure environment variables
   devenv shell
   ```

3. **Initialize Configuration**:
   ```bash
   # Create configuration files and .env
   devenv task run env:init-conf
   devenv task run env:build
   ```

4. **Run Database Setup**:
   ```bash
   # Migrate database
   python manage.py migrate
   # Load initial data
   python manage.py load_base_db_data
   # Collect static files
   python manage.py collectstatic --noinput
   ```

5. **Start Development Server**:
   ```bash
   # Unified server command (adapts to current mode)
   run-server
   # Server will be available at http://localhost:8118
   ```

### Submodules

The application includes git submodules for required libraries:
- `libs/endoreg-db`: Core database models and utilities  
- `libs/lx-anonymizer`: Video anonymization tools

To initialize submodules manually:
```bash
git submodule init
git submodule update --remote --recursive
```

**Note**: The devenv shell automatically handles submodule initialization.

## Advanced Configuration

### Debug Nix Variables
```nix-repl
# Nix Vars
varsNix = import ./devenv/vars.nix
varsNix {
  dataDir = "data";
  confDir = "./conf";
  djangoModuleName = "endo_api";
  host = "localhost";
  port = "8118";
}

# Full Devenv Utils submodule
pkgs = import <nixpkgs> {}
defaultNix = import ./devenv/default.nix
defaultNix {
  pkgs = pkgs;
  djangoModuleName = "endo_api";
  host = "localhost";
  port = "8118";
  dataDir = "data";
  confDir = "./conf";
  uvPackage = pkgs.uv; 
}

```

## Legacy Deployment Notes (Luxnix)

> **Note**: These manual steps are mostly automated in newer versions. This section is kept for reference and troubleshooting.

If you're using a system configured with luxnix (https://github.com/wg-lux/luxnix), you may need to run additional setup steps:

### Initial Deployment Steps:

1. **First rebuild** after activating the endo-api service takes time as dependencies are built
2. **Check logs**: `sudo journalctl -xeu endo-api-boot.service` (close and re-open for updates)
3. **Common issues**:
   - May fail initially due to timing issues with .env file creation
   - Ensure database password file exists: `/home/endoreg-service-user/endo-api/conf/db_pwd`
   - Run PostgreSQL setup: `ensure-psql` (requires sudo privileges)
4. **Restart service**: `sudo systemctl restart endo-api-boot.service`

### Manual Database Setup (if needed):

```bash
# Ensure PostgreSQL is configured
sudo -u postgres ensure-psql

# Verify database connection
python manage.py check --database default

# Run migrations if needed
python manage.py migrate
```

### Service Management:

```bash
# Check service status
sudo systemctl status endo-api-boot.service

# View real-time logs
sudo journalctl -u endo-api-boot.service -f

# Restart service
sudo systemctl restart endo-api-boot.service
```

## Security Considerations

### Development Environment:
- **Secret Keys**: Use generated secrets, never commit them to version control
- **Debug Mode**: Only enable in development environments
- **Database**: SQLite is used for development, never in production
- **CORS**: Permissive settings for local development only

### Production Environment (Luxnix):
- **Secret Management**: All secrets managed through luxnix vault system
- **SSL/TLS**: Automatically configured by luxnix deployment
- **Database**: PostgreSQL with proper authentication and encryption
- **CORS**: Restricted to known nodes and domains
- **File Permissions**: Managed by NixOS user/group permissions

### Central Node Additional Security:
- **Network Isolation**: Central nodes may have access to wider network ranges
- **Authentication**: Serves as authentication provider for local nodes
- **Data Access**: Has broader data access privileges across the network
- **Monitoring**: Enhanced logging and monitoring capabilities

## Contributing

### Code Quality:
- Follow Python/Django best practices
- Test luxnix compatibility with `test-luxnix-compatibility`
- Ensure environment variables are properly documented
- Test both development and production configurations

### Environment Changes:
- Update both `devenv.nix` and documentation when adding new environment variables
- Test compatibility with both manual and luxnix deployments
- Update the compatibility test script when adding new features

### Deployment Testing:
- Test in development environment first
- Verify luxnix compatibility
- Test central node configurations if applicable
- Document any new setup requirements

