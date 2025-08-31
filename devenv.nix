{ 
  pkgs, 
  lib, 
  config, 
  inputs, 
  baseBuildInputs, 
  ... 
}:
let
  # Import app configuration  
  appConfig = import ./app_config.nix;

  # Extract configuration values (can still be overridden by environment variables)
  dataDir = let env = builtins.getEnv "DATA_DIR"; in if env != "" then env else appConfig.paths.data;
  confDir = let env = builtins.getEnv "CONF_DIR"; in if env != "" then env else appConfig.paths.conf;
  confTemplateDir = let env = builtins.getEnv "CONF_TEMPLATE_DIR"; in if env != "" then env else appConfig.paths.confTemplate;
  djangoModuleName = let env = builtins.getEnv "DJANGO_MODULE"; in if env != "" then env else appConfig.app.djangoModule;
  http_protocol = let env = builtins.getEnv "HTTP_PROTOCOL"; in if env != "" then env else appConfig.server.protocol;
  host = let env = builtins.getEnv "DJANGO_HOST"; in if env != "" then env else appConfig.server.host;
  port = let env = builtins.getEnv "DJANGO_PORT"; in if env != "" then env else appConfig.server.port;
  base_url = let env = builtins.getEnv "BASE_URL"; in if env != "" then env else "${http_protocol}://${host}:${port}";

  # Development/Production mode detection
  # Use environment variable with fallback to development mode
  # This makes mode switching dynamic without requiring devenv rebuild
  envMode = builtins.getEnv "ENDO_API_MODE";
  detectedMode = if envMode == "production" then "production" else "development";
  isDev = detectedMode != "production";

  # Pin to specific Python 3.12 version to match pyproject.toml
  python = pkgs.python312;
  uvPackage = pkgs.uv;

  devenv_utils = import ./devenv/default.nix {
    pkgs = pkgs;
    lib = lib;
    appConfig = appConfig;
    djangoModuleName = djangoModuleName;
    host = host;
    port = port;
    base_url = base_url;
    dataDir = dataDir;
    confDir = confDir;
    confTemplateDir = confTemplateDir;
    uvPackage = uvPackage;
    isDev = isDev;
  };

  buildInputs = devenv_utils.buildInputs;
  runtimePackages = devenv_utils.runtimePackages;
  lxVars = devenv_utils.lx_vars;

  # For Debug Purposes lets export lxvars to a json file
  exportLxVars = pkgs.writeText "export-lx-vars.json" (builtins.toJSON lxVars);

in 
{
  # A dotenv file was found, while dotenv integration is currently not enabled.
  dotenv.enable = true;
  dotenv.disableHint = true;
  cachix.enable = true;
  packages = with pkgs; [
    stdenv.cc.cc
    nodejs_22
    yarn
    libglvnd
    inotify-tools 
    python312Packages.inotify-simple
    python312Packages.watchdog
    ffmpeg_6-headless
    cudaPackages.cuda_nvcc
  ] ++ runtimePackages;

  # Use modular environment configuration
  env = {
    # LD_LIBRARY_PATH with OpenGL support (critical for CUDA)
    LD_LIBRARY_PATH = "${
      with pkgs;
      lib.makeLibraryPath buildInputs
    }:/run/opengl-driver/lib:/run/opengl-driver-32/lib";
    
    # PyTorch CUDA allocation configuration
    PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
    
    # Mode indicator
    ENDO_API_MODE = if isDev then "development" else "production";
    
    # Database configuration based on mode
    DATABASE_ENGINE = if isDev then appConfig.database.dev.engine else appConfig.database.prod.engine;
    DATABASE_NAME = if isDev then appConfig.database.dev.name else appConfig.database.prod.name;
    DATABASE_HOST = if isDev then appConfig.database.dev.host else appConfig.database.prod.host;
    DATABASE_PORT = if isDev then appConfig.database.dev.port else appConfig.database.prod.port;
    DATABASE_USER = if isDev then appConfig.database.dev.user else appConfig.database.prod.user;
    DATABASE_PASSWORD = if isDev then appConfig.database.dev.password else "";
    
    # Remove GPU visibility variables - they interfere with PyTorch CUDA detection
    # NVIDIA_VISIBLE_DEVICES = "all";
    # CUDA_VISIBLE_DEVICES = "all";
  } // devenv_utils.lx_vars;

  # Comprehensive testing using enterTest
  enterTest = ''
    # Source common test functions
    source ${./test-functions.sh}
    
    # Run the test suite based on TEST_SUITE environment variable
    test_suite=''${TEST_SUITE:-quick}
    
    echo "🧪 Running DevEnv Test Suite: $test_suite"
    echo "========================================="
    
    # Track overall result
    test_result=0
    
    case "$test_suite" in
      "quick"|"q")
        run_quick_tests || test_result=1
        ;;
      "workflows"|"w") 
        run_workflow_tests || test_result=1
        ;;
      "containers"|"c")
        run_container_tests || test_result=1
        ;;
      "e2e"|"end-to-end")
        run_e2e_tests || test_result=1
        ;;
      "full"|"all"|"f")
        run_full_tests || test_result=1
        ;;
      "ci")
        run_ci_tests || test_result=1
        ;;
      *)
        echo "Unknown test suite: $test_suite"
        echo "Available: quick, workflows, containers, e2e, full, ci"
        exit 1
        ;;
    esac
    
    # Report final result
    if [ $test_result -eq 0 ]; then
        echo "✅ All tests in suite '$test_suite' passed!"
        exit 0
    else
        echo "❌ Some tests in suite '$test_suite' failed!"
        exit 1
    fi
  '';

  languages.python = {
    enable = true;
    uv = {
      enable = true;
      sync.enable = true;
    };
  };

  # Use modular scripts configuration  
  scripts = devenv_utils.scripts;

  # Use modular tasks configuration
  tasks = devenv_utils.tasks;

  # Use modular processes configuration
  processes = devenv_utils.processes;

  # Use modular containers configuration
  containers = devenv_utils.containers;

  # Use modular services configuration  
  services = devenv_utils.services;

  enterShell = ''
    # Dynamic mode detection at shell entry
    if [ -f ".mode" ]; then
      MODE_FROM_FILE=$(cat .mode 2>/dev/null | tr -d '\n' | tr -d ' ')
      if [ "$MODE_FROM_FILE" = "production" ]; then
        export ENDO_API_MODE="production"
      else
        export ENDO_API_MODE="development"
      fi
    else
      # Fallback to environment variable or default
      export ENDO_API_MODE="''${ENDO_API_MODE:-development}"
    fi

    echo "===== Endo API Development Environment ====="
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Mode: Production (PostgreSQL)"
    else
      echo "Mode: Development (SQLite)"
    fi
    echo "============================================="
    
    git submodule init
    git submodule update --remote --recursive

    export SYNC_CMD="uv sync"

    # Ensure dependencies are synced using uv
    # Check if venv exists. If not, run sync verbosely. If it exists, sync quietly.
    if [ ! -d ".devenv/state/venv" ]; then
       echo "Virtual environment not found. Running initial uv sync..."
       $SYNC_CMD || echo "Error: Initial uv sync failed. Please check network and pyproject.toml."
    else
       # Sync quietly if venv exists
       echo "Syncing Python dependencies with uv..."
       $SYNC_CMD --quiet || echo "Warning: uv sync failed. Environment might be outdated."
    fi

    # Activate Python virtual environment managed by uv
    ACTIVATED=false
    if [ -f ".devenv/state/venv/bin/activate" ]; then
      source .devenv/state/venv/bin/activate
      ACTIVATED=true
      echo "Virtual environment activated."
    else
      echo "Warning: uv virtual environment activation script not found. Run 'devenv task run env:clean' and re-enter shell."
    fi

    echo "Exporting environment variables from .env file..."
    if [ -f ".env" ]; then
      set -a
      source .env
      set +a
      echo ".env file loaded successfully."
    elif [ -f "local_settings.py" ]; then
      echo "Detected luxnix managed environment - using system environment variables"
      echo "No .env file needed"
    else
      echo "Warning: .env file not found. Please run 'devenv task run env:build' to create it."
    fi

    ${if isDev then ''
      # Development mode setup will be done dynamically
      if [ "$ENDO_API_MODE" = "development" ]; then
        echo "Development mode: SQLite database will be used"
        echo "Local PostgreSQL service available via 'devenv up postgres'"
      fi
    '' else ''
      # Production mode setup will be done dynamically  
      if [ "$ENDO_API_MODE" = "production" ]; then
        echo "Production mode: Expecting external PostgreSQL and Redis services"
        echo "Ensure your database connection settings are properly configured"
      fi
    ''}

    # Dynamic mode messaging
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Production mode: Expecting external PostgreSQL and Redis services"
      echo "Ensure your database connection settings are properly configured"
    else
      echo "Development mode: SQLite database will be used"
      echo "Local PostgreSQL service available via 'devenv up postgres'"
    fi

    gpu-check
  '';
}
