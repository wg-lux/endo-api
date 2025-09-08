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
  # Use the current user's home directory from environment (devenv-native approach)
  homeDir = let env = builtins.getEnv "HOME_DIR"; in if env != "" then env else builtins.getEnv "HOME";
  djangoModuleName = let env = builtins.getEnv "DJANGO_MODULE"; in if env != "" then env else appConfig.app.djangoModule;
  http_protocol = let env = builtins.getEnv "HTTP_PROTOCOL"; in if env != "" then env else appConfig.server.protocol;
  host = let env = builtins.getEnv "DJANGO_HOST"; in if env != "" then env else appConfig.server.host;
  port = let env = builtins.getEnv "DJANGO_PORT"; in if env != "" then env else appConfig.server.port;
  base_url = let env = builtins.getEnv "BASE_URL"; in if env != "" then env else "${http_protocol}://${host}:${port}";

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
    homeDir = homeDir;
    uvPackage = uvPackage;
    isDev = true; # Mode is no longer controlled by Nix; derive at runtime via DJANGO_ENV
  };

  buildInputs = devenv_utils.buildInputs;
  runtimePackages = devenv_utils.runtimePackages;
  lxVars = devenv_utils.lx_vars;

  # For Debug Purposes lets export lxvars to a json file
  exportLxVars = pkgs.writeText "export-lx-vars.json" (builtins.toJSON lxVars);

in 
{
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

  # Lean environment: no app mode or DB configuration here
  env = { } // devenv_utils.lx_vars;

  enterTest = ''
    TEST_SUITE_VAR="''${TEST_SUITE:-quick}"
    echo "🧪 Running DevEnv Test Suite: $TEST_SUITE_VAR"
    echo "========================================="
    test_result=0
    case "$TEST_SUITE_VAR" in
      "quick"|"q")
        echo "🚀 Running quick validation tests..."
        bash scripts/core/system-validation.sh --skip-containers || test_result=1
        ;;
      "workflows"|"w") 
        echo "🔄 Running workflow validation tests..."
        bash scripts/core/system-validation.sh --skip-containers || test_result=1
        echo "🔧 Testing environment setup..."
        python3 scripts/core/setup.py --status-only || test_result=1
        ;;
      "containers"|"c")
        echo "🐳 Running container validation tests..."
        bash scripts/core/system-validation.sh || test_result=1
        ;;
      "e2e"|"end-to-end")
        echo "🎯 Running end-to-end validation tests..."
        bash scripts/core/system-validation.sh || test_result=1
        ;;
      "full"|"all"|"f")
        echo "🌟 Running complete system validation..."
        bash scripts/core/system-validation.sh --verbose || test_result=1
        ;;
      "ci")
        echo "🤖 Running CI-optimized validation..."
        bash scripts/core/system-validation.sh --skip-containers || test_result=1
        ;;
      *)
        echo "Unknown test suite: $TEST_SUITE_VAR"
        echo "Available: quick, workflows, containers, e2e, full, ci"
        exit 1
        ;;
    esac
    if [ $test_result -eq 0 ]; then
        echo "✅ All tests in suite '$TEST_SUITE_VAR' passed!"
        exit 0
    else
        echo "❌ Some tests in suite '$TEST_SUITE_VAR' failed!"
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

  scripts = devenv_utils.scripts;
  tasks = devenv_utils.tasks;
  processes = devenv_utils.processes;
  containers = devenv_utils.containers;
  services = devenv_utils.services;

  enterShell = ''
    echo "===== Endo API Development Environment ====="
    MODE_MSG=''${DJANGO_ENV:-development}
    echo "Env: $MODE_MSG"
    echo "============================================="
    
    git submodule init
    git submodule update --remote --recursive

    export SYNC_CMD="uv sync"

    if [ ! -d ".devenv/state/venv" ]; then
       echo "Virtual environment not found. Running initial uv sync..."
       $SYNC_CMD || echo "Error: Initial uv sync failed. Please check network and pyproject.toml."
    else
       echo "Syncing Python dependencies with uv..."
       $SYNC_CMD --quiet || echo "Warning: uv sync failed. Environment might be outdated."
    fi

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
    else
      echo "Note: .env not found. Defaults apply."
    fi

    gpu-check
  '';
}
