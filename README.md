# Endo API
**Modern Django Endoscopy API with Unified DevEnv Management**

A sophisticated Django application for endoscopy data processing and management, built with modern DevOps practices, unified container management, and streamlined development/production workflows.

## 🚀 Quick Start

### Prerequisites
- **Nix** with flakes support
- **direnv** for automatic environment loading
- **Docker or Podman** for containers

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
manage docker-prod-build && manage docker-prod-run
```

## 🎯 Key Features

### ✅ **Unified Management System**
- **Single Command Interface**: `manage` command for all operations
- **Mode-Aware Operations**: Automatically adapts to development/production
- **Zero Configuration Drift**: Centralized settings via `app_config.nix`

### ✅ **Modern DevEnv Integration**
- **DevEnv shell for local development**: Reproducible environment via Nix
- **Automatic Environment**: Shell loads with all dependencies ready
- **CUDA Support**: GPU acceleration for ML workloads

### ✅ **Streamlined Development**
- **Development**: SQLite + Django dev server
- **Production**: PostgreSQL + Daphne ASGI server
- **Containers**: Standard Docker/Podman images with env-first overrides

### ✅ **Enterprise Ready**
- **Luxnix Compatibility**: Automatic coordination node configuration
- **Comprehensive Validation**: System health monitoring with JSON reports
- **Professional Organization**: Clean architecture with full documentation

## 📋 Management Commands

### Core Commands
```bash
manage help                    # Show all available commands
manage status                  # Show current configuration
manage setup                   # Complete environment and dependency setup
```

### Environment Management
```bash
manage dev                     # Switch to development mode (SQLite)
manage prod                    # Switch to production mode (PostgreSQL)
```

### Container Operations (Docker/Podman)
```bash
manage docker-dev-build        # Build development image
manage docker-dev-run          # Run development container
manage docker-prod-build       # Build production image
manage docker-prod-run         # Run production container
manage docker-logs [dev|prod]  # Tail container logs
manage docker-stop             # Stop containers (dev and prod)
manage docker-clean            # Remove images and containers
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
- **Containers**: Build and run checks for dev/prod Docker/Podman images

### Usage Examples
```bash
# Full system validation
bash scripts/core/system-validation.sh

# JSON-only output for automation
bash scripts/core/system-validation.sh --json-only

# Parse validation results
cat status-summary.json | jq '.tests | to_entries[] | select(.value.result == "FAIL")'
```

## 🔐 Secret Management

**Security-First Approach**: Secrets are never baked into the Nix store or committed to version control.

### Database Passwords
- **Development**: SQLite requires no password
- **Production**: Provide via environment variables
- **Containers**: No credentials baked into images

### Environment Variables
```bash
# Secrets are read from environment at runtime
DJANGO_SECRET_KEY=""             # Set via .env or environment
```

### Best Practices
- All secret files are in `.gitignore` (`.env`, `.secrets`, `conf/`)
- Use `manage setup` to generate defaults
- Override defaults with environment variables in production
- Never hardcode secrets in `app_config.nix` or other Nix files

### Files Excluded from Version Control
```
.env*                 # Environment files
.secrets              # Secret files  
*.secret              # Any secret files
conf/                 # Configuration directory (contains db_pwd)
```

## 🔐 Production configuration (env-first)

- Required: `DJANGO_SECRET_KEY`
- Database priority:
  1) `DATABASE_URL` (e.g. `postgresql://user:pass@host:5432/db`)
  2) `DB_ENGINE`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`
- Optional security flags: `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`, `DJANGO_SECURE_SSL_REDIRECT`, `DJANGO_SESSION_COOKIE_SECURE`, `DJANGO_CSRF_COOKIE_SECURE`
- Optional DB SSL via env:
  - `DJANGO_DB_OPTIONS` (JSON) takes precedence
  - Or `DB_SSLMODE`, `DB_SSLROOTCERT`/`DB_SSLROOTCERT_B64`, `DB_SSLCERT`/`DB_SSLCERT_B64`, `DB_SSLKEY`/`DB_SSLKEY_B64`

Kubernetes example (Secrets/ConfigMaps)
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
    value: "api.example.com"
  - name: DJANGO_DEBUG
    value: "false"
```

## 🧭 Common Workflows

### Quick Development Setup
```bash
# Complete setup in one command
manage dev && manage setup && devenv up
```

### Container Development
```bash
# Build and run development container
manage docker-dev-build && manage docker-dev-run
```

### Production Deployment
```bash
# Full production deployment
manage prod && manage deploy
```

### Production Containers
```bash
# Build and run production containers
manage prod && manage docker-prod-build && manage docker-prod-run
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
├── README.md                   # 📘 Comprehensive usage guide
├── core/                       # 🎯 Essential operations
│   ├── environment.py          # Environment configuration
│   ├── setup.py               # Initial environment setup
│   └── system-validation.sh   # System validation with JSON output
├── database/                   # 🗄️ Database utilities
│   ├── ensure_psql.py          # PostgreSQL setup
│   ├── fetch_db_pwd_file.py   # Password management
│   └── make_conf.py           # Configuration generation
├── utilities/                  # 🛠️ General utilities
│   ├── gpu-check.py           # GPU diagnostics
│   └── test_luxnix_compatibility.py # Compatibility testing
├── cuda/                      # ⚙️ CUDA diagnostics
│   └── [Specialized CUDA tools]
└── archive/                   # 🗃️ Legacy/completed scripts
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
3. **Rebuild if Needed**: `manage docker-*-build` (for containers)

### Environment Variables
The system supports environment variable overrides:

```bash
export DJANGO_PORT=8080         # Override default port
export DJANGO_ENV=production    # Override mode
manage status                   # Verify changes
```

---

*Last updated: September 2025*  
*System Version: DevEnv Unified Management v2.1 (Docker/Podman)*
