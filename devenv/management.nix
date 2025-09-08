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
    "-e DB_CONFIG_FILE=/app/${appConfig.paths.conf}/db.yaml"
    # Do NOT mount whole workspace to avoid permission issues
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

    # Container Management - Using DevEnv Native Containers
    "container:build" = {
      description = "Build DevEnv container for current mode";
      exec = ''
        echo "🔨 Building DevEnv container for mode: $ENDO_API_MODE"
        
        MODE_SUFFIX=$([[ "$ENDO_API_MODE" == "production" ]] && echo "prod" || echo "dev")
        
        echo "Building native DevEnv container: $MODE_SUFFIX"
        echo "⏱️  This may take a few minutes for the first build..."
        
        # Build the DevEnv container using native devenv container system
        CONTAINER_SPEC=$(timeout 600 devenv container build "$MODE_SUFFIX" 2>&1 | tee /tmp/devenv-build.log)
        
        BUILD_EXIT_CODE=$?
        
        if [ $BUILD_EXIT_CODE -eq 0 ]; then
          # Extract the container specification path from the output
          SPEC_PATH=$(echo "$CONTAINER_SPEC" | grep -E '^/nix/store.*\.json$' | head -1)
          
          if [ -n "$SPEC_PATH" ]; then
            echo "✅ DevEnv container built successfully"
            echo "Container specification: $SPEC_PATH"
            echo ""
            echo "Next steps:"
            echo "  1. Run 'manage copy' to load into your local container runtime"
            echo "  2. Run 'manage run' to start the container"
          else
            echo "⚠️  Container built but couldn't find specification path"
            cat /tmp/devenv-build.log
          fi
        elif [ $BUILD_EXIT_CODE -eq 124 ]; then
          echo "❌ DevEnv container build timed out (10 minutes)"
          echo "Build log saved to /tmp/devenv-build.log"
          exit 1
        else
          echo "❌ Container build failed"
          cat /tmp/devenv-build.log
          exit 1
        fi
      '';
    };

    "container:copy" = {
      description = "Copy DevEnv container to container runtime (Docker/Podman)";
      exec = ''
        echo "📦 Loading DevEnv container image into local container runtime..."
        
        MODE_SUFFIX=$([[ "$ENDO_API_MODE" == "production" ]] && echo "prod" || echo "dev")
        
        # Detect available container runtime
        CONTAINER_RUNTIME=""
        if command -v podman >/dev/null 2>&1; then
          CONTAINER_RUNTIME="podman"
          echo "🐳 Using Podman as container runtime"
        elif command -v docker >/dev/null 2>&1; then
          CONTAINER_RUNTIME="docker"
          echo "🐳 Using Docker as container runtime"
        else
          echo "❌ No container runtime found (neither Docker nor Podman)"
          exit 1
        fi
        
        # Choose correct local transport for skopeo via devenv container copy
        if [ "$CONTAINER_RUNTIME" = "podman" ]; then
          REGISTRY_TRANSPORT="containers-storage:"
        else
          REGISTRY_TRANSPORT="docker-daemon://"
        fi
        
        echo "⏱️  Importing image into $CONTAINER_RUNTIME (this may take several minutes)..."
        if timeout 900 devenv container --registry "$REGISTRY_TRANSPORT" copy "$MODE_SUFFIX"; then
          echo "✅ Image loaded into $CONTAINER_RUNTIME successfully"
          
          # Verify the image exists
          IMAGE_NAME="endo-api-$MODE_SUFFIX"
          if $CONTAINER_RUNTIME images "$IMAGE_NAME" | grep -q "$IMAGE_NAME"; then
            echo "✅ Container image verified: $IMAGE_NAME:latest"
            echo ""
            echo "Available container images:"
            $CONTAINER_RUNTIME images | grep endo-api | head -5 || true
            echo ""
            echo "Ready to run! Use 'manage run' to start the container"
          else
            echo "⚠️  Import completed but image not listed by $CONTAINER_RUNTIME"
          fi
        else
          COPY_EXIT_CODE=$?
          if [ $COPY_EXIT_CODE -eq 124 ]; then
            echo "❌ Container copy timed out (15 minutes)"
          else  
            echo "❌ Failed to load image into $CONTAINER_RUNTIME"
          fi
          echo "You can still use 'devenv container run $MODE_SUFFIX' directly (uses Docker CLI)"
          exit 1
        fi
      '';
    };

    "container:run" = {
      description = "Run DevEnv container for current mode";
      exec = ''
        echo "🚀 Running DevEnv container for mode: $ENDO_API_MODE"
        
        MODE_SUFFIX=$([[ "$ENDO_API_MODE" == "production" ]] && echo "prod" || echo "dev")
        CONTAINER_NAME="endo-api-$MODE_SUFFIX"
        INSTANCE_NAME="$CONTAINER_NAME"
        
        # Detect available container runtime
        CONTAINER_RUNTIME=""
        if command -v podman >/dev/null 2>&1; then
          CONTAINER_RUNTIME="podman"
        elif command -v docker >/dev/null 2>&1; then
          CONTAINER_RUNTIME="docker"  
        else
          echo "❌ No container runtime found (neither Docker nor Podman)"
          echo "Falling back to DevEnv native container run..."
          
          # Fallback to DevEnv native run (slower but doesn't require Docker/Podman)
          echo "Starting DevEnv container: $MODE_SUFFIX"
          echo "⏱️  Initial start may take 8-10 minutes to build shell environment..."
          if timeout 720 devenv container run "$MODE_SUFFIX"; then
            echo "✅ DevEnv container started successfully"
            return 0
          else
            echo "❌ DevEnv container run failed or timed out (12 minutes)"
            return 1
          fi
        fi
        
        echo "🐳 Using $CONTAINER_RUNTIME as container runtime"
        
        # Check if image exists in container runtime
        if ! $CONTAINER_RUNTIME images "$CONTAINER_NAME" | grep -q "$CONTAINER_NAME"; then
          echo "❌ Container image '$CONTAINER_NAME:latest' not found in $CONTAINER_RUNTIME"
          echo ""
          echo "Please run the following commands first:"
          echo "  1. manage build           # Build the DevEnv container"
          echo "  2. manage copy            # Load into $CONTAINER_RUNTIME"
          echo "  3. manage run             # Start the container"
          exit 1
        fi
        
        echo "✅ Found container image: $CONTAINER_NAME:latest"
        
        # GPU support detection
        ${gpuArgs}
        
        # Stop existing container if running
        if $CONTAINER_RUNTIME ps -q -f name="$INSTANCE_NAME" | grep -q .; then
          echo "🛑 Stopping existing container: $INSTANCE_NAME"
          $CONTAINER_RUNTIME stop "$INSTANCE_NAME" 2>/dev/null || $CONTAINER_RUNTIME kill "$INSTANCE_NAME" 2>/dev/null || true
        fi
        
        # Remove existing container
        $CONTAINER_RUNTIME rm "$INSTANCE_NAME" 2>/dev/null || true
        
        echo "🚀 Starting container: $INSTANCE_NAME"
        echo "⏱️  Initial startup may take 1-2 minutes to setup environment..."
        
        # Start the container using cached image
        if $CONTAINER_RUNTIME run -d \
          --name "$INSTANCE_NAME" \
          ${builtins.concatStringsSep " \\\n  " (commonContainerArgs "$ENDO_API_MODE")} \
          $GPU_ARGS \
          "$CONTAINER_NAME:latest"; then
          
          echo "✅ Container started: $INSTANCE_NAME"
          echo ""
          echo "Container Info:"
          echo "  Name: $INSTANCE_NAME"
          echo "  Image: $CONTAINER_NAME:latest"  
          echo "  Runtime: $CONTAINER_RUNTIME"
          echo "  Access: http://localhost:${appConfig.server.port}"
          echo ""
          echo "Useful commands:"
          echo "  $CONTAINER_RUNTIME logs -f $INSTANCE_NAME    # View logs"
          echo "  $CONTAINER_RUNTIME exec -it $INSTANCE_NAME bash  # Shell access"
          echo "  manage stop                                   # Stop container"
          
        else
          echo "❌ Failed to start container with $CONTAINER_RUNTIME"
          exit 1
        fi
      '';
    };

    "container:stop" = {
      description = "Stop containers";
      exec = ''
        echo "🛑 Stopping containers..."
        
        # Detect available container runtime
        CONTAINER_RUNTIME=""
        if command -v podman >/dev/null 2>&1; then
          CONTAINER_RUNTIME="podman"
        elif command -v docker >/dev/null 2>&1; then
          CONTAINER_RUNTIME="docker"  
        else
          echo "⚠️  No container runtime found (neither Docker nor Podman)"
          echo "Cannot stop containers via container runtime"
          exit 0
        fi
        
        echo "🐳 Using $CONTAINER_RUNTIME to stop containers"
        
        # Stop Docker/Podman containers (both regular and test containers)
        for mode in dev prod; do
          # Stop regular containers (used by manage run)
          CONTAINER_NAME="endo-api-$mode"
          
          if $CONTAINER_RUNTIME ps -q -f name="$CONTAINER_NAME" | grep -q .; then
            echo "Stopping container: $CONTAINER_NAME"
            if $CONTAINER_RUNTIME stop "$CONTAINER_NAME" 2>/dev/null; then
              echo "✅ Successfully stopped $CONTAINER_NAME"
            else
              echo "⚠️  Normal stop failed, trying force kill..."
              if $CONTAINER_RUNTIME kill "$CONTAINER_NAME" 2>/dev/null; then
                echo "✅ Force killed $CONTAINER_NAME"
              else
                echo "❌ Failed to stop $CONTAINER_NAME"
              fi
            fi
          fi
          
          # Also stop test containers (used by test suite)
          TEST_INSTANCE_NAME="$CONTAINER_NAME-test"
          if $CONTAINER_RUNTIME ps -q -f name="$TEST_INSTANCE_NAME" | grep -q .; then
            echo "Stopping test container: $TEST_INSTANCE_NAME"
            if $CONTAINER_RUNTIME stop "$TEST_INSTANCE_NAME" 2>/dev/null; then
              echo "✅ Successfully stopped $TEST_INSTANCE_NAME"
            else
              echo "⚠️  Normal stop failed, trying force kill..."
              if $CONTAINER_RUNTIME kill "$TEST_INSTANCE_NAME" 2>/dev/null; then
                echo "✅ Force killed $TEST_INSTANCE_NAME"
              else
                echo "❌ Failed to stop $TEST_INSTANCE_NAME"
              fi
            fi
          fi
        done
        
        echo "✅ Stop operation completed"
      '';
    };

    "container:remove" = {
      description = "Remove containers and clean up";
      exec = ''
        echo "🗑️  Removing containers..."
        
        # Remove Docker containers (both regular and test containers)
        for mode in dev prod; do
          CONTAINER_NAME="endo-api-$mode"
          
          # Remove regular containers
          if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
            docker stop "$CONTAINER_NAME" 2>/dev/null || docker kill "$CONTAINER_NAME" 2>/dev/null || true
          fi
          
          if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
            if docker rm -f "$CONTAINER_NAME" 2>/dev/null; then
              echo "✅ Removed Docker container: $CONTAINER_NAME"
            else
              echo "❌ Failed to remove $CONTAINER_NAME"
            fi
          fi
          
          # Remove test containers
          TEST_INSTANCE_NAME="$CONTAINER_NAME-test"
          if docker ps -q -f name="$TEST_INSTANCE_NAME" | grep -q .; then
            docker stop "$TEST_INSTANCE_NAME" 2>/dev/null || docker kill "$TEST_INSTANCE_NAME" 2>/dev/null || true
          fi
          
          if docker ps -aq -f name="$TEST_INSTANCE_NAME" | grep -q .; then
            if docker rm -f "$TEST_INSTANCE_NAME" 2>/dev/null; then
              echo "✅ Removed test container: $TEST_INSTANCE_NAME"
            else
              echo "❌ Failed to remove $TEST_INSTANCE_NAME"
            fi
          fi
        done
        
        echo "✅ Remove operation completed"
      '';
    };

    "container:cleanup" = {
      description = "Clean up all container images and instances";
      exec = ''
        echo "🧹 Cleaning up containers and images..."
        
        # Remove containers first
        devenv tasks run container:remove
        
        # Remove Docker images
        for mode in dev prod; do
          IMAGE_NAME="endo-api-$mode"
          if docker images -q "$IMAGE_NAME" 2>/dev/null | grep -q .; then
            echo "Removing Docker image: $IMAGE_NAME"
            docker rmi "$IMAGE_NAME:latest" 2>/dev/null || docker rmi -f "$IMAGE_NAME:latest" 2>/dev/null || true
          fi
        done
        
        # Clean up DevEnv container build artifacts (if any)
        echo "Cleaning up DevEnv container artifacts..."
        rm -f /tmp/devenv-build.log 2>/dev/null || true
        
        echo "✅ Cleanup complete"
      '';
    };

    "container:cleanup-tests" = {
      description = "Clean up test containers specifically";
      exec = ''
        echo "🧪 Cleaning up test containers..."
        
        # Define test container names
        TEST_CONTAINERS=("endo-api-dev-test" "endo-api-prod-test" "endo-api-processes-test")
        
        for container in "''${TEST_CONTAINERS[@]}"; do
          # Stop if running
          if docker ps -q -f name="$container" | grep -q .; then
            echo "Stopping test container: $container"
            docker stop "$container" 2>/dev/null || docker kill "$container" 2>/dev/null || true
          fi
          
          # Remove if exists
          if docker ps -aq -f name="$container" | grep -q .; then
            echo "Removing test container: $container"
            docker rm -f "$container" 2>/dev/null || true
          fi
        done
        
        echo "✅ Test container cleanup complete"
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
        "copy")
          devenv tasks run container:copy
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
          # Detect container runtime for status output
          CONTAINER_RUNTIME=""
          if command -v podman >/dev/null 2>&1; then
            CONTAINER_RUNTIME="podman"
          elif command -v docker >/dev/null 2>&1; then
            CONTAINER_RUNTIME="docker"
          fi

          if [ -n "$CONTAINER_RUNTIME" ]; then
            echo "Running Containers ($CONTAINER_RUNTIME):"
            $CONTAINER_RUNTIME ps --filter "name=${appConfig.app.name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
          else
            echo "Running Containers:"
            echo "(no container runtime available)"
          fi
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
          echo "  manage copy      - Load container image into local engine"
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
          echo "  manage dev && manage build && manage copy && manage run"
          echo "  manage prod && manage deploy"
          ;;
      esac
    '';

    # Server management (mode-aware)
    "run-server".exec = ''
      export DJANGO_HOST="''${DJANGO_HOST:-${appConfig.server.host}}"
      export DJANGO_PORT="''${DJANGO_PORT:-${appConfig.server.port}}"
      bash scripts/core/server-run.sh
    '';

    # Container server (for use inside containers)
    "run-server-container".exec = ''
      export DJANGO_HOST=${appConfig.server.containerHost}
      export ENDO_API_MODE=''${ENDO_API_MODE:-development}
      # Use absolute path inside image where repo is copied to /
      bash /scripts/core/server-run.sh
    '';

    # GPU diagnostics
    "gpu-check".exec = "${pkgs.uv}/bin/uv run python scripts/utilities/gpu-check.py";
  };
}
