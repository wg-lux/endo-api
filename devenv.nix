{ 
  pkgs, 
  lib, 
  config, 
  inputs, 
  baseBuildInputs, 
  ... 
}:
let
  # Replace hardcoded values with environment variables, providing fallbacks
  dataDir = let env = builtins.getEnv "DATA_DIR"; in if env != "" then env else (let env2 = builtins.getEnv "STORAGE_DIR"; in if env2 != "" then env2 else "./data");
  confDir = let env = builtins.getEnv "CONF_DIR"; in if env != "" then env else "./conf";
  confTemplateDir = let env = builtins.getEnv "CONF_TEMPLATE_DIR"; in if env != "" then env else "./conf_template";
  djangoModuleName = let env = builtins.getEnv "DJANGO_MODULE"; in if env != "" then env else "endo_api";
  http_protocol = let env = builtins.getEnv "HTTP_PROTOCOL"; in if env != "" then env else "http";
  host = let env = builtins.getEnv "DJANGO_HOST"; in if env != "" then env else "localhost";
  port = let env = builtins.getEnv "DJANGO_PORT"; in if env != "" then env else "8118";
  base_url = let env = builtins.getEnv "BASE_URL"; in if env != "" then env else "${http_protocol}://${host}:${port}";

  # Pin to specific Python 3.12 version to match pyproject.toml
  python = pkgs.python312;
  uvPackage = pkgs.uv;

  devenv_utils = import ./devenv/default.nix {
    pkgs = pkgs;
    djangoModuleName = djangoModuleName;
    host = host;
    port = port;
    base_url = base_url;
    dataDir = dataDir;
    confDir = confDir;
    confTemplateDir = confTemplateDir;
    uvPackage = uvPackage;
  };

  buildInputs = devenv_utils.buildInputs ++ [ pkgs.zlib ];
  runtimePackages = devenv_utils.runtimePackages;
  lxVars = devenv_utils.lx_vars;

  # For Debug Purposes lets export lxvars to a json file
  exportLxVars = pkgs.writeText "export-lx-vars.json" (builtins.toJSON lxVars);

in 
{
  # A dotenv file was found, while dotenv integration is currently not enabled.
  dotenv.enable = true;
  dotenv.disableHint = true;

  packages = runtimePackages ++ buildInputs;

  env = {
    LD_LIBRARY_PATH = "${
      with pkgs;
      lib.makeLibraryPath buildInputs
    }:/run/opengl-driver/lib:/run/opengl-driver-32/lib";
  } // lxVars;

  languages.python = {
    enable = true;
    uv = {
      enable = true;
      sync.enable = true;
    };
  };

  scripts = {
    

    set-prod-settings.exec = "${pkgs.uv}/bin/uv run python scripts/set_production_settings.py";
    set-dev-settings.exec = "${pkgs.uv}/bin/uv run python scripts/set_development_settings.py";
    set-central-settings.exec = "${pkgs.uv}/bin/uv run python scripts/set_central_settings.py";
    
    test-luxnix-compatibility.exec = "${pkgs.uv}/bin/uv run python scripts/test_luxnix_compatibility.py";

    run-dev-server.exec = ''

      env-pipe
      set-dev-settings
      echo "Running dev server"
      echo "Host: ${host}"
      echo "Port: ${port}"
      deploy-pipe
      ${pkgs.uv}/bin/uv run python manage.py runserver ${host}:${port}
    '';

    env-pipe.exec = ''
      # Skip local config generation if local_settings.py exists (luxnix managed)
      if [ ! -f "local_settings.py" ]; then
        env-init-conf
        env-build
      else
        echo "Detected luxnix managed environment (local_settings.py exists)"
        echo "Skipping local configuration generation"
      fi
      env-export
    '';

    deploy-pipe.exec = ''
      deploy-migrate
      deploy-load-base-db-data
      deploy-collectstatic
    '';

    run-prod-server.exec = ''
  
      env-pipe
      # Detect if running in luxnix environment and use appropriate settings
      if [ "$CENTRAL_NODE" = "true" ]; then
        echo "Running as central node"
        set-central-settings
      else
        set-prod-settings
      fi
      echo "Running production server"
      echo "Port: ${port}"


      # print settings module and other important variables for transparency
      echo "DJANGO_SETTINGS_MODULE: $DJANGO_SETTINGS_MODULE"
      echo "BASE_URL: $BASE_URL"

      deploy-pipe
      ${pkgs.uv}/bin/uv run daphne ${djangoModuleName}.asgi:application -p ${port}
    '';

    gpu-check.exec = "${pkgs.uv}/bin/uv run python scripts/gpu-check.py";

    ensure-psql.exec = "${pkgs.uv}/bin/uv run python scripts/ensure_psql.py";
    env-fetch-db-pwd-file.exec = "${pkgs.uv}/bin/uv run python scripts/fetch_db_pwd_file.py";
    env-init-conf.exec = "${pkgs.uv}/bin/uv run python scripts/make_conf.py";
    env-build.exec = "${pkgs.uv}/bin/uv run env_setup.py";
    env-export.exec = ''
      set -a
      source .env
      set +a
      echo ".env file loaded successfully."
      echo "DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE"
    '';
    deploy-migrate.exec = "${pkgs.uv}/bin/uv run python manage.py migrate";
    deploy-load-base-db-data.exec = "${pkgs.uv}/bin/uv run python manage.py load_base_db_data";
    deploy-collectstatic.exec = "${pkgs.uv}/bin/uv run python manage.py collectstatic --noinput";
  };


  tasks = {
    "env:fetch-db-pwd-file" = {
      description = "Fetch the database password file";
      exec = "${pkgs.uv}/bin/uv run python scripts/fetch_db_pwd_file.py";
    };
    "env:init-conf" = {
      # after = ["env:psql-pwd-file-exists" "devenv:enterShell"];
      exec = "${pkgs.uv}/bin/uv run python scripts/make_conf.py";
    };
    "env:build" = {
      description = "Build the .env file";
      after = ["env:init-conf"];
      exec = "uv run env_setup.py";
      # status = "test -f .env";
    };

    "deploy:migrate" = { 
      exec = "${pkgs.uv}/bin/uv run python manage.py migrate";
    };
    "deploy:load-base-db-data" = {
      after = ["deploy:migrate"];
      exec = "${pkgs.uv}/bin/uv run python manage.py load_base_db_data";
    };
    "deploy:collectstatic" = {
      after = ["deploy:load-base-db-data"];
      exec = "${pkgs.uv}/bin/uv run python manage.py collectstatic --noinput";
    };


  };

  processes = {
    django.exec = "run-prod-server";
  };

  enterShell = ''
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

    gpu-check

  '';
}

