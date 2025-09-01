# Endo API
**Modern Django Endoscopy API with Unified DevEnv Management**

A sophisticated Django application for endoscopy data processing and management, built with modern DevOps practices, unified container management, and streamlined development/production workflows.

## 🚀 Quick Start

### Prerequisites
- **Nix** with flakes support
- **direnv** for automatic environment loading
- **Docker** (optional, for containers)

### 1. Initialize Environment
```bash
git clone <repository-url>
cd endo-api
direnv allow                    # Enable automatic environment loading
manage setup                   # Complete environment setup
```

### 2. Development Workflow
```bash
manage dev                     # Switch to development mode
devenv up                      # Start Django server
# Server accessible at http://localhost:8118
```

### 3. Production Workflow
```bash
manage prod                    # Switch to production mode
manage deploy                  # Complete deployment pipeline
# Or use containers:
manage build && manage run     # Build and run production container
```

## 🎯 Key Features

### ✅ **Unified Management System**
- **Single Command Interface**: `manage` command for all operations
- **Mode-Aware Operations**: Automatically adapts to development/production
- **Zero Configuration Drift**: Centralized settings via `app_config.nix`

### ✅ **Modern DevEnv Integration**
- **Native DevEnv Containers**: Full container support with caching
- **Automatic Environment**: Shell loads with all dependencies ready
- **CUDA Support**: GPU acceleration for ML workloads

### ✅ **Streamlined Development**
- **Development**: SQLite + Django dev server
- **Production**: PostgreSQL + Daphne ASGI server
- **Containers**: Docker/Podman with DevEnv integration

### ✅ **Enterprise Ready**
- **Luxnix Compatibility**: Automatic coordination node configuration
- **Comprehensive Validation**: System health monitoring with JSON reports
- **Professional Organization**: Clean architecture with full documentation

## 📋 Management Commands

### Core Commands
```bash
manage help                    # Show all available commands
manage status                  # Show current configuration and running containers
manage setup                   # Complete environment and dependency setup
```

### Environment Management
```bash
manage dev                     # Switch to development mode (SQLite)
manage prod                    # Switch to production mode (PostgreSQL)
```

### Container Operations
```bash
manage build                   # Build container for current mode
manage run                     # Run container for current mode
manage stop                    # Stop all running containers
manage restart                 # Restart containers
manage clean                   # Clean up containers and images
```

### Deployment
```bash
manage deploy                  # Full deployment pipeline (production)
```

### System Validation
```bash
# Run comprehensive system validation
bash scripts/core/system-validation.sh

# Generate JSON status report only
bash scripts/core/system-validation.sh --json-only

# Fast validation (skip slow container builds)
bash scripts/core/system-validation.sh --skip-containers

# Force rebuild containers (for fresh validation)
bash scripts/core/system-validation.sh --force-rebuild

# Verbose mode (show full build output)
bash scripts/core/system-validation.sh --verbose

# View detailed system status
cat status-summary.json | jq '.summary'
```

## 🔍 System Validation

The application includes comprehensive system validation with JSON reporting:

### Validation Features
- **File Structure**: Validates all required files and directories
- **Environment**: Tests unified environment management
- **Database**: Validates connectivity and configuration
- **CUDA/GPU**: Hardware compatibility testing
- **Containers**: Automated build and run validation with smart caching
- **Legacy Compatibility**: Backwards compatibility verification

**Container Optimization**: Uses cached validation containers (`endo-api-dev-test:validation`, `endo-api-prod-test:validation`) to speed up repeated validations. Only rebuilds when containers don't exist or `--force-rebuild` is specified.

### Usage Examples
```bash
# Full system validation
bash scripts/core/system-validation.sh

# JSON-only output for automation
bash scripts/core/system-validation.sh --json-only

# Parse validation results
cat status-summary.json | jq '.tests | to_entries[] | select(.value.result == "FAIL")'
```

### JSON Output Structure
```json
{
  "timestamp": "2025-01-XX",
  "validation_port": 10123,
  "summary": {
    "total_tests": 12,
    "passed": 10,
    "warnings": 2,
    "failed": 0
  },
  "tests": {
    "file_structure": {"result": "PASS", "message": "All required files present"},
    "container_dev_build": {"result": "PASS", "message": "Dev container builds successfully"},
    "environment_config": {"result": "PASS", "message": "Environment management working"}
  },
  "environment": {
    "devenv_active": true,
    "django_settings": "endo_api.settings_prod",
    "endo_api_mode": "production"
  }
}
```

## � Secret Management

**Security-First Approach**: Secrets are never baked into the Nix store or committed to version control.

### Database Passwords
- **Development**: SQLite requires no password
- **Production**: Password stored in `conf/db_pwd` (auto-generated during setup)
- **Containers**: Mount `conf/` directory as volume for secure access

### Environment Variables
```bash
# Secrets are read from environment or external files at runtime
DATABASE_PASSWORD=""              # Always empty in Nix configuration
DJANGO_SECRET_KEY=""             # Set via .env or environment
```

### Best Practices
- All secret files are in `.gitignore` (`.env`, `.secrets`, `conf/`)
- Use `manage setup` to generate secure default passwords
- Override defaults with environment variables in production
- Never hardcode secrets in `app_config.nix` or other Nix files

### Files Excluded from Version Control
```
.env*                 # Environment files
.secrets              # Secret files  
*.secret              # Any secret files
conf/                 # Configuration directory (contains db_pwd)
```

## �🚀 Common Workflows

### Quick Development Setup
```bash
# Complete setup in one command
manage dev && manage setup && devenv up
```

### Container Development
```bash
# Build and run development container
manage dev && manage build && manage run
```

### Production Deployment
```bash
# Full production deployment
manage prod && manage deploy
```

### Production Containers
```bash
# Build and run production containers
manage prod && manage build && manage run
```

### System Health Check
```bash
# Validate system and generate report
bash scripts/core/system-validation.sh
cat status-summary.json | jq '.summary'
```

## 🔧 DevEnv Commands

### Core DevEnv Integration
```bash
# Start services based on current mode
start-services                 # Mode-aware service startup
services-up                    # Service management
services-down                  # Stop all services
services-logs                  # Follow service logs

# Database operations
db-shell                       # Connect to database (mode-aware)

# Environment setup
env-build                      # Build .env file from templates
env-export                     # Export environment variables
```

### Script Integration
```bash
# Environment configuration (unified)
set-dev-settings              # Configure development environment
set-prod-settings             # Configure production environment  
set-central-settings          # Configure central node environment

# Utility scripts
gpu-check                     # GPU/CUDA diagnostics
ensure-psql                   # PostgreSQL availability check
```

## 🏗️ Architecture

### Mode-Based Configuration
The application operates in two primary modes that automatically configure all components:

| Component | Development Mode | Production Mode |
|-----------|------------------|-----------------|
| **Database** | SQLite (local file) | PostgreSQL (external) |
| **Server** | Django dev server | Daphne ASGI server |
| **Host Binding** | localhost/127.0.0.1 | 0.0.0.0 |
| **Debug Mode** | Enabled | Disabled |
| **Static Files** | Served by Django | Collected for nginx |
| **Dependencies** | Local services available | External services expected |

### Scripts Organization
```
scripts/
├── README.md                   # � Comprehensive usage guide
├── core/                       # 🎯 Essential operations
│   ├── environment.py          # Environment configuration
│   ├── setup.py               # Initial environment setup
│   └── system-validation.sh   # System validation with JSON output
├── database/                   # �️ Database utilities
│   ├── ensure_psql.py          # PostgreSQL setup
│   ├── fetch_db_pwd_file.py   # Password management
│   └── make_conf.py           # Configuration generation
├── utilities/                  # � General utilities
│   ├── gpu-check.py           # GPU diagnostics
│   └── test_luxnix_compatibility.py # Compatibility testing
├── cuda/                      # � CUDA diagnostics
│   └── [Specialized CUDA tools]
└── archive/                   # � Legacy/completed scripts
    └── [Historical implementations]
```

### Directory Structure
```
endo-api/
├── app_config.nix              # 🔧 Centralized configuration
├── devenv.nix                  # 🐚 Development environment
├── manage                      # 🎮 Unified management script
├── devenv/                     # 📦 Modular DevEnv components
├── container/                  # 🐳 Container infrastructure
├── scripts/                    # 🔨 Organized utility scripts
├── endo_api/                   # 🐍 Django application
├── data/                       # 💾 Application data
└── docs/                       # 📚 Documentation and guides
```

### DevEnv Components
```
devenv/
├── management.nix              # 🎯 Unified management system
├── scripts.nix                # 🔄 Core DevEnv scripts
├── containers.nix              # 🐳 Container definitions
├── environment.nix             # 🌍 Environment variables
├── build_inputs.nix            # 📚 System dependencies
└── runtime_packages.nix        # 🏃 Runtime packages
```

### Container Infrastructure
```
container/
├── Dockerfile.dev              # 🏗️ Development container
├── Dockerfile.prod             # 🏭 Production container
├── docker-entrypoint.sh        # 🚀 Development entrypoint
├── docker-entrypoint-prod.sh   # 🚀 Production entrypoint
└── README.md                   # 📖 Container documentation
```

## 🔧 Configuration

### Centralized Configuration
All application settings are managed through `app_config.nix`:

```nix
{
  app = {
    name = "endo-api";
    djangoModule = "endo_api";
    version = "1.0.0";
  };
  
  server = {
    host = "localhost";
    port = "8118";
    protocol = "http";
  };
  
  # ... additional settings
}
```

### Customization
To customize the application:

1. **Edit Configuration**: Modify `app_config.nix`
2. **Reload Environment**: `direnv reload`
3. **Rebuild if Needed**: `manage build` (for containers)

### Environment Variables
The system supports environment variable overrides:

```bash
export DJANGO_PORT=8080         # Override default port
export ENDO_API_MODE=production # Override mode
manage status                   # Verify changes
```

## 🐳 Container Support

### Native DevEnv Containers
Built-in container support with DevEnv integration:

```bash
# Development container
manage dev && manage build      # Build development image
manage run                      # Run development container

# Production container  
manage prod && manage build     # Build production image
manage run                      # Run production container
```

### Container Features
- **Fast Builds**: Multi-layer caching with Nix
- **Consistent Environments**: Same Nix packages in containers and shells
- **GPU Support**: CUDA acceleration when available
- **Volume Management**: Automatic data and config volume mounting

### Docker Compose Alternative
For those preferring docker-compose workflows:

```bash
# Traditional approach still supported
docker-compose up               # Uses generated configurations
```

## 🛠️ Development

### Local Development
```bash
manage dev                      # Set development mode
devenv shell                    # Enter development shell
run-server                      # Start Django development server
```

### Database Management
```bash
# Development (SQLite)
devenv tasks run db:migrate     # Run migrations
devenv tasks run db:load-data   # Load sample data

# Production (PostgreSQL) - requires external database
manage prod                     # Switch to production mode
manage deploy                   # Run full deployment pipeline
```

### Testing
```bash
# Run tests
python manage.py test

# GPU testing
gpu-check                       # Check CUDA availability
```

## 🚀 Deployment

### Production Deployment
```bash
manage prod                     # Switch to production mode
manage deploy                   # Full deployment pipeline
```

The deployment pipeline includes:
1. Database migrations
2. Static file collection
3. Base data loading
4. Service startup

### Container Deployment
```bash
manage prod                     # Switch to production mode
manage build                    # Build production container
manage run                      # Deploy container
manage status                   # Verify deployment
```

### Luxnix Managed Deployment
For luxnix-managed environments, deployment is automatic:

- **Detection**: Automatically detects luxnix environment
- **Configuration**: Uses `local_settings.py` when available
- **Secrets**: Integrates with luxnix vault system
- **Central Nodes**: Supports coordination node setup

## 🚨 Troubleshooting

### Common Issues

#### Environment Setup Problems
```bash
# Check environment status
python scripts/core/environment.py --status

# Reset environment
python scripts/core/environment.py --clean
python scripts/core/setup.py
```

#### Container Build Failures
```bash
# Check container logs
manage logs

# Clean rebuild
docker system prune -a
manage build
```

#### Database Connection Issues
```bash
# Check database configuration
manage db-shell
bash scripts/database/postgres-check.py

# Reset database
manage migrate-reset
```

#### CUDA/GPU Problems
```bash
# Run comprehensive GPU diagnostics
python scripts/cuda/gpu-check.py
python test_cuda_detailed.py
```

#### Service Startup Issues
```bash
# Check service status
services-logs

# Restart services
services-down && services-up
```

### Getting Help

1. **Check validation report**: Run `bash scripts/core/system-validation.sh` to get comprehensive system status
2. **Review logs**: Use `manage logs` or `services-logs` to examine service output
3. **Verify environment**: Ensure `devenv shell` is active and mode is set correctly
4. **Check documentation**: Refer to `docs/` for detailed implementation guides

### Performance Optimization

- Use `manage prod` for production workloads
- Container builds are cached - use `manage build --no-cache` only when needed
- Database operations are optimized for the configured mode
- GPU acceleration is automatically detected and used when available

## 📚 Documentation

- **[Centralized Configuration Guide](docs/CENTRALIZED_CONFIG_GUIDE.md)**: Comprehensive configuration management
- **[DevEnv Testing](docs/devenv-testing.md)**: Testing and validation procedures
- **[Container Guide](docs/NATIVE_DEVENV_CONTAINERS_GUIDE.md)**: Container integration documentation
- **[Implementation Reports](docs/implementation-reports/)**: Technical implementation details

## 🤝 Contributing

1. **Development Setup**:
   ```bash
   manage dev
   python scripts/core/setup.py
   devenv up
   ```

2. **Testing Changes**:
   ```bash
   bash scripts/core/system-validation.sh
   python tests/test_*.py
   ```

3. **Container Validation**:
   ```bash
   manage build
   manage run
   ```

4. **Code Standards**: Follow the established patterns in `scripts/core/` for new functionality.

## 📄 License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

---

*Last updated: January 2025*  
*System Version: DevEnv Unified Management v2.0*
