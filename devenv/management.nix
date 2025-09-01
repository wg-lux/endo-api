# Centralized Management for Endo API
# =====================================
# 
# This file consolidates all management tasks, scripts, and container operations
# into a unified DevEnv-based approach using the centralized configuration.

{ pkgs, lib, appConfig, isDev ? false }:
let
  # Utility functions
  containerName = mode: "${appConfig.app.name}-${mode}-test";
  
  # Common container runtime arguments
  commonContainerArgs = mode: [
    "-p ${appConfig.server.port}:${appConfig.server.port}"
    "-e ENDO_API_MODE=${mode}"
    "-e DJANGO_HOST=${appConfig.server.containerHost}"
    "-e DJANGO_PORT=${appConfig.server.port}"
    "-e DJANGO_MODULE=${appConfig.app.djangoModule}"
    "-v $(pwd)/${appConfig.paths.data}:/app/${appConfig.paths.data}"
    "-v $(pwd)/${appConfig.paths.conf}:/app/${appConfig.paths.conf}"
    "-v $(pwd)/staticfiles:/app/staticfiles"
  ];

  # GPU support detection
  gpuArgs = ''
    GPU_ARGS=""
    if command -v nvidia-smi &> /dev/null; then
      if docker info 2>/dev/null | grep -q "nvidia"; then
        GPU_ARGS="--gpus all"
        echo "🎯 NVIDIA GPU support enabled (Docker)"
      elif command -v podman &> /dev/null; then
        # Check each device file individually and only add if it exists
        DEVICE_ARGS=""
        
        # Check for primary GPU device
        if [ -c "/dev/nvidia0" ]; then
          DEVICE_ARGS="$DEVICE_ARGS --device /dev/nvidia0:/dev/nvidia0"
        fi
        
        # Check for NVIDIA control device
        if [ -c "/dev/nvidiactl" ]; then
          DEVICE_ARGS="$DEVICE_ARGS --device /dev/nvidiactl:/dev/nvidiactl"
        fi
        
        # Check for NVIDIA Unified Memory device
        if [ -c "/dev/nvidia-uvm" ]; then
          DEVICE_ARGS="$DEVICE_ARGS --device /dev/nvidia-uvm:/dev/nvidia-uvm"
        fi
        
        # Check for NVIDIA mode setting device
        if [ -c "/dev/nvidia-modeset" ]; then
          DEVICE_ARGS="$DEVICE_ARGS --device /dev/nvidia-modeset:/dev/nvidia-modeset"
        fi
        
        # Always add only device mappings if any device was found
        if [ ! -z "$DEVICE_ARGS" ]; then
          GPU_ARGS="$DEVICE_ARGS"
          echo "🎯 NVIDIA GPU support enabled (Podman) - devices: $DEVICE_ARGS"
        else
          echo "⚠️  NVIDIA tools detected but no device files found in /dev/"
        fi
      else
        echo "⚠️  GPU detected but no container GPU runtime available"
      fi
    fi
  '';
in
{
  # =============================================================================
  # UNIFIED TASK DEFINITIONS
  # =============================================================================
  
  tasks = {
    # Environment Management
    "env:setup" = {
      description = "Complete environment setup (replaces multiple scripts)";
      exec = ''
        echo "🔧 Setting up Endo API environment..."
        
        # Step 1: Mode detection and setup
        if [ -f ".mode" ]; then
          export ENDO_API_MODE=$(cat .mode 2>/dev/null | tr -d '\n' | tr -d ' ')
        else
          export ENDO_API_MODE="''${ENDO_API_MODE:-development}"
          echo "$ENDO_API_MODE" > .mode
        fi
        
        echo "Mode: $ENDO_API_MODE"
        
        # Step 2: Ensure WORKING_DIR is set (fallback to current directory)
        export WORKING_DIR="''${WORKING_DIR:-$(pwd)}"
        
        # Step 3: Create directories
        mkdir -p ${appConfig.paths.data} ${appConfig.paths.conf} staticfiles
        mkdir -p ${appConfig.paths.data}/{import,export,videos,frames,pdfs,model_weights,logs}
        
        # Step 4: Configuration setup (use existing scripts)
        ${pkgs.uv}/bin/uv run python scripts/database/make_conf.py
        
        # Step 5: Environment file setup
        ${pkgs.uv}/bin/uv run python scripts/core/setup.py
        
        # Step 5: CUDA environment setup
        devenv tasks run env:setup-cuda
        
        echo "✅ Environment setup complete!"
      '';
    };

    "env:setup-cuda" = {
      description = "Setup CUDA environment for PyTorch";
      exec = ''
        echo "🎯 Setting up CUDA environment..."
        export CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}
        export CUDA_ROOT=$CUDA_HOME
        export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$CUDA_HOME/lib:$LD_LIBRARY_PATH"
        export PATH="$CUDA_HOME/bin:$PATH"
        
        python -c "
import torch
import os
print('CUDA Environment Check:')
print('======================')
print('CUDA_HOME:', os.environ.get('CUDA_HOME', 'Not set'))
print('PyTorch version:', torch.__version__)
print('PyTorch CUDA version:', torch.version.cuda if hasattr(torch.version, 'cuda') else 'N/A')
print('CUDA available:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('CUDA device count:', torch.cuda.device_count())
    for i in range(torch.cuda.device_count()):
        print(f'Device {i}: {torch.cuda.get_device_name(i)}')
        print(f'  Memory: {torch.cuda.get_device_properties(i).total_memory / (1024**3):.1f} GB')
else:
    print('CUDA not available - possible causes:')
    print('  - No NVIDIA GPU')
    print('  - Missing NVIDIA drivers')
    print('  - Missing container GPU runtime')
    print('  - PyTorch CPU-only build')
"
      '';
    };

    # Container Management
    "container:build" = {
      description = "Build container for current mode";
      exec = ''
        echo "🔨 Building container for mode: $ENDO_API_MODE"
        
        MODE_SUFFIX=$([[ "$ENDO_API_MODE" == "production" ]] && echo "prod" || echo "dev")
        CONTAINER_NAME="${appConfig.app.name}-$MODE_SUFFIX"
        
        echo "Building DevEnv container: $CONTAINER_NAME"
        devenv container build "$CONTAINER_NAME"
        
        echo "Copying to Docker daemon..."
        devenv container copy "$CONTAINER_NAME"
        
        # Tag properly - use devenv's container name to find the correct image
        echo "Finding and tagging container image..."
        
        # DevEnv creates images with predictable naming, look for our specific container
        IMAGE_ID=$(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | grep "$CONTAINER_NAME" | head -1 | awk '{print $3}')
        
        # Fallback: if devenv naming doesn't match, look for the most recent image without a name
        if [ -z "$IMAGE_ID" ]; then
          echo "Primary lookup failed, trying fallback method..."
          IMAGE_ID=$(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | grep "^<none>" | head -1 | awk '{print $3}')
        fi
        
        # Final fallback: get the most recently created image (dangerous but better than failing)
        if [ -z "$IMAGE_ID" ]; then
          echo "⚠️  Fallback: Using most recent image (may be incorrect)"
          IMAGE_ID=$(docker images -q --format "table {{.CreatedAt}}\t{{.ID}}" | sort -r | head -1 | awk '{print $2}')
        fi
        
        if [ ! -z "$IMAGE_ID" ]; then
          echo "Found image ID: $IMAGE_ID"
          docker tag "$IMAGE_ID" "$CONTAINER_NAME:latest"
          echo "✅ Container ready: $CONTAINER_NAME:latest"
          
          # Verify the tag worked
          if docker images "$CONTAINER_NAME:latest" | grep -q "$CONTAINER_NAME"; then
            echo "✅ Tag verification successful"
          else
            echo "⚠️  Tag verification failed, but continuing..."
          fi
        else
          echo "❌ Failed to find container image"
          echo "Available images:"
          docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}"
          exit 1
        fi
      '';
    };

    "container:run" = {
      description = "Run container for current mode";
      exec = ''
        echo "🚀 Running container for mode: $ENDO_API_MODE"
        
        MODE_SUFFIX=$([[ "$ENDO_API_MODE" == "production" ]] && echo "prod" || echo "dev")
        CONTAINER_NAME="${appConfig.app.name}-$MODE_SUFFIX"
        INSTANCE_NAME="$CONTAINER_NAME-test"
        
        # GPU support detection
        ${gpuArgs}
        
        # Stop existing container with improved error handling
        echo "Stopping existing container if running..."
        if docker ps -q -f name="$INSTANCE_NAME" | grep -q .; then
          echo "Found running container: $INSTANCE_NAME"
          if docker stop "$INSTANCE_NAME" 2>/dev/null; then
            echo "✅ Successfully stopped $INSTANCE_NAME"
          else
            echo "⚠️  Failed to stop $INSTANCE_NAME, attempting force kill..."
            docker kill "$INSTANCE_NAME" 2>/dev/null || echo "⚠️  Force kill also failed, continuing anyway..."
          fi
        else
          echo "No running container named $INSTANCE_NAME found"
        fi
        
        # Remove existing container with improved error handling
        echo "Removing existing container if present..."
        if docker ps -aq -f name="$INSTANCE_NAME" | grep -q .; then
          echo "Found existing container: $INSTANCE_NAME"
          if docker rm "$INSTANCE_NAME" 2>/dev/null; then
            echo "✅ Successfully removed $INSTANCE_NAME"
          else
            echo "⚠️  Failed to remove $INSTANCE_NAME, attempting force removal..."
            if docker rm -f "$INSTANCE_NAME" 2>/dev/null; then
              echo "✅ Force removal successful"
            else
              echo "❌ Force removal failed, but continuing with new container creation..."
            fi
          fi
        else
          echo "No existing container named $INSTANCE_NAME found"
        fi
        
        # Run new container
        echo "Starting container: $INSTANCE_NAME"
        docker run -d \
          --name "$INSTANCE_NAME" \
          ${builtins.concatStringsSep " \\\n  " (commonContainerArgs "$ENDO_API_MODE")} \
          $GPU_ARGS \
          "$CONTAINER_NAME:latest"
        
        echo "✅ Container started: $INSTANCE_NAME"
        echo "   Access: http://localhost:${appConfig.server.port}"
        echo "   Logs: docker logs -f $INSTANCE_NAME"
      '';
    };

    "container:stop" = {
      description = "Stop containers";
      exec = ''
        echo "🛑 Stopping containers..."
        for mode in dev prod; do
          INSTANCE_NAME="${appConfig.app.name}-$mode-test"
          if docker ps -q -f name="$INSTANCE_NAME" | grep -q .; then
            echo "Stopping $INSTANCE_NAME..."
            if docker stop "$INSTANCE_NAME" 2>/dev/null; then
              echo "✅ Successfully stopped $INSTANCE_NAME"
            else
              echo "⚠️  Normal stop failed for $INSTANCE_NAME, trying force kill..."
              if docker kill "$INSTANCE_NAME" 2>/dev/null; then
                echo "✅ Force killed $INSTANCE_NAME"
              else
                echo "❌ Failed to stop $INSTANCE_NAME (may already be stopped)"
              fi
            fi
          else
            echo "No running container named $INSTANCE_NAME found"
          fi
        done
        echo "✅ Stop operation completed"
      '';
    };

    "container:remove" = {
      description = "Remove containers";
      exec = ''
        echo "🗑️  Removing containers..."
        for mode in dev prod; do
          INSTANCE_NAME="${appConfig.app.name}-$mode-test"
          if docker ps -aq -f name="$INSTANCE_NAME" | grep -q .; then
            echo "Removing $INSTANCE_NAME..."
            # First try to stop if running
            if docker ps -q -f name="$INSTANCE_NAME" | grep -q .; then
              echo "Container is running, stopping first..."
              docker stop "$INSTANCE_NAME" 2>/dev/null || docker kill "$INSTANCE_NAME" 2>/dev/null || true
            fi
            
            # Now remove the container
            if docker rm "$INSTANCE_NAME" 2>/dev/null; then
              echo "✅ Successfully removed $INSTANCE_NAME"
            else
              echo "⚠️  Normal removal failed for $INSTANCE_NAME, trying force removal..."
              if docker rm -f "$INSTANCE_NAME" 2>/dev/null; then
                echo "✅ Force removed $INSTANCE_NAME"
              else
                echo "❌ Failed to remove $INSTANCE_NAME (may not exist)"
              fi
            fi
          else
            echo "No container named $INSTANCE_NAME found"
          fi
        done
        echo "✅ Remove operation completed"
      '';
    };

    "container:cleanup" = {
      description = "Clean up all container images and instances";
      exec = ''
        echo "🧹 Cleaning up containers and images..."
        
        # Remove containers
        devenv tasks run container:remove
        
        # Remove images
        for mode in dev prod; do
          IMAGE_NAME="${appConfig.app.name}-$mode"
          if docker images -q "$IMAGE_NAME" | grep -q .; then
            docker rmi "$IMAGE_NAME:latest" 2>/dev/null || true
            echo "✅ Removed image $IMAGE_NAME:latest"
          fi
        done
        
        echo "✅ Cleanup complete"
      '';
    };

    # Database Management
    "db:migrate" = {
      description = "Run database migrations";
      exec = "${pkgs.uv}/bin/uv run python manage.py migrate";
    };

    "db:load-data" = {
      description = "Load base database data";
      after = ["db:migrate"];
      exec = "${pkgs.uv}/bin/uv run python manage.py load_base_db_data";
    };

    "db:collectstatic" = {
      description = "Collect static files";
      after = ["db:load-data"];
      exec = "${pkgs.uv}/bin/uv run python manage.py collectstatic --noinput";
    };

    # Deployment Pipeline
    "deploy:full" = {
      description = "Complete deployment pipeline";
      after = ["env:setup"];
      exec = ''
        echo "🚀 Running deployment pipeline..."
        devenv tasks run db:migrate
        devenv tasks run db:load-data  
        devenv tasks run db:collectstatic
        echo "✅ Deployment pipeline complete"
      '';
    };

    # Testing Tasks
            # No test tasks defined here - use devenv test directly with TEST_SUITE environment variable
        # Example: TEST_SUITE=quick devenv test
  };

  # =============================================================================
  # UNIFIED SCRIPT DEFINITIONS
  # =============================================================================

  scripts = {
    # Main management commands
    "manage".exec = ''
      case "''${1:-help}" in
        "setup")
          echo "🔧 Setting up Endo API..."
          devenv tasks run env:setup
          ;;
        "dev")
          echo "development" > .mode
          echo "🔄 Switched to development mode"
          devenv tasks run env:setup
          ;;
        "prod") 
          echo "production" > .mode
          echo "🔄 Switched to production mode"
          devenv tasks run env:setup
          ;;
        "build")
          devenv tasks run container:build
          ;;
        "run")
          devenv tasks run container:run
          ;;
        "stop")
          devenv tasks run container:stop
          ;;
        "restart")
          devenv tasks run container:stop
          sleep 2
          devenv tasks run container:run
          ;;
        "clean")
          devenv tasks run container:cleanup
          ;;
        "deploy")
          devenv tasks run deploy:full
          ;;
        "test")
          case "''${2:-quick}" in
            "quick"|"q")
              TEST_SUITE=quick devenv test
              ;;
            "workflows"|"w")
              TEST_SUITE=workflows devenv test
              ;;
            "containers"|"c")
              TEST_SUITE=containers devenv test
              ;;
            "e2e"|"end-to-end")
              TEST_SUITE=e2e devenv test
              ;;
            "full"|"f"|"all")
              TEST_SUITE=full devenv test
              ;;
            "ci")
              TEST_SUITE=ci devenv test
              ;;
            *)
              echo "Available test suites:"
              echo "  manage test quick      - Quick core functionality tests"
              echo "  manage test workflows  - Development/production workflow tests"
              echo "  manage test containers - Container build and runtime tests"
              echo "  manage test e2e        - End-to-end workflow tests" 
              echo "  manage test full       - Complete test suite"
              echo "  manage test ci         - CI/CD compatible tests"
              ;;
          esac
          ;;
        "status")
          echo "Current Configuration:"
          echo "====================="
          echo "Mode: $(cat .mode 2>/dev/null || echo 'development')"
          echo "App: ${appConfig.app.name}"
          echo "Port: ${appConfig.server.port}"
          echo "Host: ${appConfig.server.host}"
          echo ""
          echo "Running Containers:"
          docker ps --filter "name=${appConfig.app.name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
          ;;
        "help"|*)
          echo "Endo API Management Commands"
          echo "============================"
          echo ""
          echo "Environment:"
          echo "  manage setup     - Complete environment setup"
          echo "  manage dev       - Switch to development mode"
          echo "  manage prod      - Switch to production mode"
          echo ""
          echo "Containers:"  
          echo "  manage build     - Build container for current mode"
          echo "  manage run       - Run container for current mode"
          echo "  manage stop      - Stop all containers"
          echo "  manage restart   - Restart containers"
          echo "  manage clean     - Clean up all containers and images"
          echo ""
          echo "Deployment:"
          echo "  manage deploy    - Run full deployment pipeline"
          echo "  manage status    - Show current status"
          echo ""
          echo "Testing:"
          echo "  manage test quick      - Quick core functionality tests"
          echo "  manage test workflows  - Development/production workflow tests"
          echo "  manage test containers - Container build and runtime tests"
          echo "  manage test e2e        - End-to-end workflow tests"
          echo "  manage test full       - Complete test suite"
          echo "  manage test ci         - CI/CD compatible tests"
          echo ""
          echo "Examples:"
          echo "  manage dev && manage build && manage run"
          echo "  manage prod && manage deploy"
          ;;
      esac
    '';

    # Server management (mode-aware)
    "run-server".exec = ''
      # Load mode
      export ENDO_API_MODE=$(cat .mode 2>/dev/null || echo 'development')
      
      # Runtime configuration
      RUNTIME_HOST=''${DJANGO_HOST:-${appConfig.server.host}}
      RUNTIME_PORT=''${DJANGO_PORT:-${appConfig.server.port}}
      
      echo "🌟 Starting Endo API Server"
      echo "Mode: $ENDO_API_MODE"
      echo "Host: $RUNTIME_HOST"
      echo "Port: $RUNTIME_PORT"
      echo ""
      
      # Ensure environment is ready
      if [ ! -f ".env" ]; then
        echo "📝 Environment file missing, setting up..."
        devenv tasks run env:setup
      fi
      
      # Run deployment pipeline if needed
      if [ "$ENDO_API_MODE" = "production" ]; then
        echo "🚀 Running deployment pipeline..."
        devenv tasks run deploy:full
        # Production server
        ${pkgs.uv}/bin/uv run daphne ${appConfig.app.djangoModule}.asgi:application -b $RUNTIME_HOST -p $RUNTIME_PORT
      else
        # Development server
        echo "🛠️  Running development server..."
        devenv tasks run db:migrate
        ${pkgs.uv}/bin/uv run python manage.py runserver $RUNTIME_HOST:$RUNTIME_PORT
      fi
    '';

    # Container server (for use inside containers)
    "run-server-container".exec = ''
      export DJANGO_HOST=${appConfig.server.containerHost}
      export ENDO_API_MODE=''${ENDO_API_MODE:-development}
      run-server
    '';

    # GPU diagnostics
    "gpu-check".exec = "${pkgs.uv}/bin/uv run python scripts/utilities/gpu-check.py";
  };
}
