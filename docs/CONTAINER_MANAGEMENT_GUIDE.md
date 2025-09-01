# Container Management Guide for Endo API

## Overview

The Endo API project uses a **streamlined container approach** that prioritizes DevEnv native containers with Docker as a fallback. This approach provides the best of both worlds: DevEnv's powerful development environment capabilities with Docker's widespread compatibility.

## Architecture

### Container Strategy

1. **Primary**: DevEnv Native Containers
   - Built using `devenv container build <name>`
   - Includes full development environment (Nix, Python, dependencies)
   - Provides reproducible, isolated environments

2. **Fallback**: Docker Containers  
   - Used when DevEnv containers fail or are not available
   - Built from traditional Dockerfiles (for legacy support)
   - Provides broader compatibility

### Container Types

#### Development Container (`dev`)
- **Purpose**: Full development environment with all tools
- **Command**: `devenv container build dev`
- **Startup**: `run-server-container` (Django development server)
- **Use Case**: Local development, testing, debugging

#### Production Container (`prod`)  
- **Purpose**: Optimized runtime with minimal dependencies
- **Command**: `devenv container build prod`
- **Startup**: `run-server-container` (Daphne ASGI server)
- **Use Case**: Production deployment, staging

#### Processes Container (`processes`)
- **Purpose**: Background process runner
- **Command**: `devenv container build processes`  
- **Startup**: `run-server` (process manager)
- **Use Case**: Running background services, workers

## Management Commands

### Unified Management Interface

The `manage` command provides a unified interface for all container operations:

```bash
# Environment setup
manage setup          # Complete environment setup
manage dev            # Switch to development mode
manage prod           # Switch to production mode

# Container operations
manage build          # Build container for current mode
manage run            # Run container for current mode
manage stop           # Stop all containers
manage restart        # Restart containers
manage clean          # Clean up containers and images

# Status and information
manage status         # Show current configuration and running containers
```

### Mode-Aware Operations

All container operations are **mode-aware**:
- Development mode builds and runs development containers
- Production mode builds and runs production containers
- Mode switching automatically updates configuration

## Container Build Process

### DevEnv Container Build

1. **Configuration**: Uses `devenv/containers.nix` configuration
2. **Build**: Creates container specification in Nix store
3. **Copy**: Optionally copies to Docker daemon
4. **Tag**: Tags image for easy identification

```bash
manage build
# ↓
# 🔨 Building DevEnv container for mode: development
# Building native DevEnv container: dev
# ✅ DevEnv container built successfully
# Container specification: /nix/store/...-image-endo-api-dev.json
# Copying container to Docker daemon...
# ✅ Container copied to Docker daemon
```

### Fallback Docker Build

If DevEnv container build fails, the system falls back to traditional Docker builds:

```bash
# Uses container/Dockerfile.dev or container/Dockerfile.prod
docker build -f container/Dockerfile.dev -t endo-api-dev .
```

## Container Run Process

### Primary: DevEnv Container Run

1. **Native Run**: Uses `devenv container run <name>`
2. **Environment**: Full DevEnv environment available
3. **Networking**: Binds to configured ports
4. **GPU**: Automatic GPU support if available

### Fallback: Docker Container Run

1. **Docker Run**: Uses `docker run` with appropriate flags
2. **Volume Mounts**: Maps data, config, and static files
3. **Environment Variables**: Passes all necessary env vars
4. **GPU Support**: Detects and configures GPU runtime

## Testing and Validation

### Container Workflow Testing

Comprehensive test suite validates container operations:

```bash
# Quick smoke test
tests/test_container_workflow.sh smoke

# Test container building
tests/test_container_workflow.sh build

# Test Docker integration  
tests/test_container_workflow.sh docker

# Full test suite
tests/test_container_workflow.sh full
```

### System Validation

Integration with existing system validation:

```bash
# Run system validation with containers
bash scripts/core/system-validation.sh

# Skip container tests if needed
bash scripts/core/system-validation.sh --skip-containers
```

## Troubleshooting

### Common Issues

#### 1. DevEnv Container Build Fails

**Symptoms**: `devenv container build dev` returns error
**Causes**: 
- Incorrect `copyToRoot` configuration
- Missing dependencies in Nix configuration
- DevEnv version incompatibility

**Solutions**:
```bash
# Check DevEnv version
devenv --version

# Rebuild environment
devenv shell

# Check container configuration
devenv container --help
```

#### 2. Container Not Starting

**Symptoms**: Container builds but fails to start
**Causes**:
- Port conflicts
- Missing environment variables
- Startup command issues

**Solutions**:
```bash
# Check port conflicts
netstat -tulpn | grep 8118

# Check container logs
docker logs endo-api-dev-test

# Test startup command manually
devenv shell -- run-server-container
```

#### 3. Old Container Images

**Symptoms**: `docker images` shows old containers
**Causes**:
- Cached images not cleaned up
- Build process not updating tags
- Multiple container strategies conflicting

**Solutions**:
```bash
# Clean all container artifacts
manage clean

# Force rebuild
manage build

# Remove old images manually
docker rmi $(docker images | grep endo-api | awk '{print $3}')
```

### Docker Integration Issues

#### Image Not Found

```bash
# List available images
docker images | grep endo-api

# If no DevEnv images, try copying again
devenv container copy dev
```

#### Permission Errors

```bash
# Check Docker daemon permissions
docker info

# Add user to docker group (requires restart)
sudo usermod -aG docker $USER
```

### DevEnv Specific Issues

#### Container Module Not Available

```bash
# Update DevEnv
nix profile upgrade devenv

# Check if containers are enabled
devenv container --help
```

#### Build Timeouts

```bash
# Increase timeout for large builds
timeout 3600 devenv container build dev
```

## Configuration Files

### Key Configuration Files

- `devenv/containers.nix`: DevEnv container definitions
- `devenv/management.nix`: Container management tasks
- `container/Dockerfile.dev`: Development Docker fallback
- `container/Dockerfile.prod`: Production Docker fallback
- `container/docker-entrypoint*.sh`: Container startup scripts

### Environment Variables

Important environment variables for containers:

- `ENDO_API_MODE`: development/production
- `DJANGO_HOST`: Host binding (0.0.0.0 for containers)
- `DJANGO_PORT`: Port binding (8118 default)
- `DJANGO_SETTINGS_MODULE`: Django settings module

## Best Practices

### Development Workflow

1. **Setup**: `manage dev && manage setup`
2. **Build**: `manage build` 
3. **Run**: `manage run`
4. **Test**: `tests/test_container_workflow.sh smoke`
5. **Cleanup**: `manage clean` when done

### Production Deployment

1. **Switch Mode**: `manage prod`
2. **Build**: `manage build`
3. **Test**: Validate with system-validation.sh
4. **Deploy**: `manage run`
5. **Monitor**: `manage status`

### Troubleshooting Workflow

1. **Check Status**: `manage status`
2. **Review Logs**: `docker logs <container-name>`
3. **Test Components**: Run individual test suites
4. **Clean Environment**: `manage clean` and rebuild
5. **Fallback**: Use Docker containers if DevEnv fails

## Performance Considerations

### Build Optimization

- DevEnv containers cache Nix dependencies
- Docker builds use multi-stage builds
- Container images include only necessary components

### Runtime Optimization

- Development containers include debugging tools
- Production containers use optimized startup
- GPU support is automatically detected and configured

### Resource Management

- Containers respect system resource limits
- Memory and CPU usage are monitored
- Old containers are automatically cleaned up

## Integration with Existing Systems

### DevEnv Integration

- Full compatibility with existing DevEnv configuration
- Environment variables shared between host and containers
- Scripts and tasks work identically in containers

### Django Integration

- Container startup uses existing Django management
- Database migrations run automatically
- Static files are handled appropriately

### CI/CD Integration

- Container builds work in CI environments
- Test suites validate container functionality
- Multiple deployment targets supported
