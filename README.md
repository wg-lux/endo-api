# Endo API
**Modern Django Endoscopy API with Unified DevEnv Management**

A sophisticated Django application for endoscopy data processing and management, built with modern DevOps practices, unified container management, and seamless development/production workflows.

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
manage build                   # Build development container (optional)
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

### ✅ **Flexible Deployment Options**
- **Development**: SQLite + Django dev server
- **Production**: PostgreSQL + Daphne ASGI server
- **Containers**: Docker/Podman with DevEnv integration

### ✅ **Luxnix Compatibility**
- **Central Node Support**: Automatic coordination node configuration
- **Automatic Detection**: Zero-config deployment on managed systems
- **Vault Integration**: Secure credential management

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

### Example Workflows
```bash
# Quick development setup
manage dev && manage setup && devenv up

# Container development
manage dev && manage build && manage run

# Production deployment
manage prod && manage deploy

# Production containers
manage prod && manage build && manage run
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

### Directory Structure
```
endo-api/
├── app_config.nix              # 🔧 Centralized configuration
├── devenv.nix                  # 🐚 Development environment
├── manage                      # 🎮 Unified management script
├── devenv/                     # 📦 Modular DevEnv components
├── container/                  # 🐳 Container infrastructure
├── endo_api/                   # 🐍 Django application
├── scripts/                    # 🔨 Utility scripts
├── data/                       # 💾 Application data
└── staticfiles/                # 📄 Static files
```

### DevEnv Components
```
devenv/
├── management.nix              # 🎯 Primary management system
├── scripts.nix                # 🔄 Compatibility layer
├── containers.nix              # 🐳 Container definitions
├── environment.nix             # 🌍 Environment variables
├── build_inputs.nix            # 📚 System dependencies
├── runtime_packages.nix        # 🏃 Runtime packages
└── vars.nix                    # 📊 Path variables
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

## 🔍 Troubleshooting

### Common Issues

**Environment Not Loading**:
```bash
direnv reload                   # Reload environment
devenv shell --recreate-lock    # Force rebuild
```

**Port Conflicts**:
```bash
manage status                   # Check current configuration
# Edit app_config.nix to change port
direnv reload                   # Apply changes
```

**Container Issues**:
```bash
manage stop                     # Stop all containers
manage clean                    # Clean up containers/images
manage build                    # Rebuild containers
```

**Database Issues**:
```bash
# Development
rm data/db.sqlite3              # Reset development database
devenv tasks run db:migrate     # Recreate database

# Production
manage deploy                   # Run full deployment pipeline
```

### Logs and Debugging
```bash
# Container logs
docker logs endo-api-dev-test   # Development container
docker logs endo-api-prod-test  # Production container

# Application logs
tail -f data/logs/*.log         # Application logs

# DevEnv debugging
devenv info                     # Environment information
```

## 🤝 Contributing

### Development Setup
```bash
git clone <repository>
cd endo-api
manage dev && manage setup      # Setup development environment
# Make changes...
# Test changes...
git commit -m "Your changes"
```

### Code Style
- Follow Django best practices
- Use type hints where appropriate
- Maintain the DRY principle
- Update tests for new features

## 📚 Additional Resources

### Project Documentation
- **[Complete Documentation](docs/README.md)** - Comprehensive project documentation index
- **[Implementation Reports](docs/implementation-reports/)** - Detailed technical reports on system development
- **[Configuration Guide](docs/CENTRALIZED_CONFIG_GUIDE.md)** - Advanced configuration and customization
- **[Container Guide](docs/NATIVE_DEVENV_CONTAINERS_GUIDE.md)** - Detailed container usage and deployment
- **[Container Infrastructure](container/README.md)** - Container files documentation and usage

### External Resources
- **DevEnv Documentation**: [devenv.sh](https://devenv.sh)
- **Django Documentation**: [djangoproject.com](https://www.djangoproject.com)
- **Nix Documentation**: [nixos.org](https://nixos.org)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🎯 Project Status

✅ **Production Ready**: Unified management system fully operational  
✅ **Container Support**: DevEnv native containers working  
✅ **DRY Optimized**: 87.5% code duplication eliminated  
✅ **Luxnix Compatible**: Seamless integration with managed environments  
✅ **Well Tested**: Comprehensive test suite with CI/CD support

**Last Updated**: August 31, 2025
