# Scripts configuration for devenv
{ 
  pkgs,
  djangoModuleName,
  host,
  port,
  isDev ? false,
  appConfig  # Centralized application configuration
}:
let
  # Common server startup logic (DRY) - now uses centralized config
  serverStartup = containerMode: let
    serverHost = if containerMode then appConfig.server.containerHost else if isDev then host else appConfig.server.containerHost;
    hostText = if containerMode then "containerized server" else "server";
  in ''
    env-pipe
    
    # Runtime port and host detection (override build-time values) - using centralized config
    RUNTIME_HOST=''${DJANGO_HOST:-${if containerMode then appConfig.server.containerHost else host}}
    RUNTIME_PORT=''${DJANGO_PORT:-${port}}
    
    # Runtime mode detection
    if [ "$ENDO_API_MODE" = "production" ]; then
      # Production mode
      # Detect if running in luxnix environment and use appropriate settings
      if [ "$CENTRAL_NODE" = "true" ]; then
        echo "Running as central node"
        set-central-settings
      else
        set-prod-settings
      fi
      echo "Starting ${hostText} in Production mode (PostgreSQL)"
      echo "Host: ${if containerMode then appConfig.server.containerHost else appConfig.server.containerHost}"
      echo "Port: $RUNTIME_PORT"
      echo "Expecting external PostgreSQL and Redis services"

      # print settings module and other important variables for transparency
      echo "DJANGO_SETTINGS_MODULE: $DJANGO_SETTINGS_MODULE"
      echo "BASE_URL: $BASE_URL"

      deploy-pipe
      ${pkgs.uv}/bin/uv run daphne ${djangoModuleName}.asgi:application -b ${if containerMode then appConfig.server.containerHost else appConfig.server.containerHost} -p $RUNTIME_PORT
    else
      # Development mode
      set-dev-settings
      echo "Starting ${hostText} in Development mode (SQLite)"
      echo "Host: ${if containerMode then appConfig.server.containerHost else "$RUNTIME_HOST"}"
      echo "Port: $RUNTIME_PORT"
      deploy-pipe
      ${pkgs.uv}/bin/uv run python manage.py runserver ${if containerMode then appConfig.server.containerHost else "$RUNTIME_HOST"}:$RUNTIME_PORT
    fi
  '';
in
{
  # Unified server commands that adapt to current mode
  run-server.exec = serverStartup false;

  # Containerized server (always binds to 0.0.0.0)  
  run-server-container.exec = serverStartup true;

} // {
  # Minimal compatibility layer for deprecated commands
  # All deprecated commands now redirect to unified management
  run-dev-server.exec = ''
    echo "⚠️  DEPRECATED: Use 'manage dev && run-server' or 'devenv up' instead"
    echo "Redirecting to unified server..."
    run-server
  '';
  
  run-prod-server.exec = ''  
    echo "⚠️  DEPRECATED: Use 'manage prod && run-server' or 'devenv up' instead"
    echo "Redirecting to unified server..."
    run-server
  '';
  
  run-dev-server-container.exec = ''
    echo "⚠️  DEPRECATED: Use 'manage dev && manage run' instead"
    echo "Redirecting to unified container management..."
    run-server-container
  '';
  
  run-prod-server-container.exec = ''
    echo "⚠️  DEPRECATED: Use 'manage prod && manage run' instead" 
    echo "Redirecting to unified container management..."
    run-server-container
  '';

  dev-up.exec = ''
    echo "⚠️  DEPRECATED: Use 'manage dev && devenv up' instead"
    echo "Redirecting to unified services..."
    start-services
  '';

} // {

  # Environment and deployment scripts
  set-prod-settings.exec = "${pkgs.uv}/bin/uv run python scripts/set_production_settings.py";
  set-dev-settings.exec = "${pkgs.uv}/bin/uv run python scripts/set_development_settings.py";
  set-central-settings.exec = "${pkgs.uv}/bin/uv run python scripts/set_central_settings.py";

  # Container management - redirected to unified management system
  container-dev-up.exec = ''
    echo "🔄 Redirecting to unified container management..."
    manage dev && manage run
  '';

  container-prod-up.exec = ''
    echo "🔄 Redirecting to unified container management..."
    manage prod && manage run
  '';

  container-help.exec = ''
    echo "=== Endo API Container Management ==="
    echo ""
    echo "🏗️  Unified Commands:"
    echo "  manage build         Build container for current mode"
    echo "  manage run           Run container for current mode"  
    echo "  manage stop          Stop all containers"
    echo "  manage clean         Clean containers and images"
    echo ""
    echo "🔧 Mode Management:"
    echo "  manage dev           Switch to development mode"
    echo "  manage prod          Switch to production mode"
    echo "  manage status        Show current status"
    echo ""
    echo "� Recommended Workflow:"
    echo "  1. manage dev              # Set development mode"
    echo "  2. manage build            # Build dev container" 
    echo "  3. manage run              # Run dev container"
    echo ""
    echo "  OR for production:"
    echo "  1. manage prod && manage build && manage run"
  '';

  container-stop.exec = ''
    echo "🔄 Redirecting to unified management..."
    manage stop
  '';

  container-clean.exec = ''
    echo "🔄 Redirecting to unified management..."
    manage clean
  '';

  # Service management (mode-aware)
  start-services.exec = ''
    # Runtime mode detection
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Starting production environment..."
      echo "Note: External PostgreSQL and Redis services expected"
      devenv up django
    else
      echo "Starting development environment with local services..."
      devenv up django postgres
    fi
  '';

  services-up.exec = ''
    # Runtime mode detection
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Production mode: Services should be managed externally"
      echo "Expecting PostgreSQL on external host"
      echo "Expecting Redis on external host"
    else
      echo "Starting development services (postgres, redis)..."
      devenv up postgres redis
    fi
  '';

  # Legacy alias (deprecated)
  dev-up.exec = ''
    echo "⚠️  DEPRECATED: Use 'start-services' instead. This command will be removed in a future version."
    echo "   Current mode: $ENDO_API_MODE"
    echo ""
    start-services
  '';

  services-down.exec = ''
    echo "Stopping all processes..."
    devenv down
  '';

  services-logs.exec = ''
    echo "Following logs for all processes..."
    devenv processes
  '';



  # Database management - redirected to unified task system
  db-shell.exec = ''
    echo "🔄 Database operations redirected to unified tasks..."
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Production mode: Use external database tools"
      echo "Example: psql -h <DB_HOST> -p <DB_PORT> -U <DB_USER> -d <DB_NAME>"
    else
      echo "Development mode: Connecting to local SQLite database"
      ${pkgs.uv}/bin/uv run python manage.py dbshell
    fi
  '';

  db-backup.exec = ''
    echo "🔄 Use 'devenv tasks run' for database operations"
    echo "Database backup should be handled appropriately for your mode:"
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Production: pg_dump -h <DB_HOST> -p <DB_PORT> -U <DB_USER> <DB_NAME> > backup.sql"
    else
      echo "Development: SQLite backup via file copy or .dump command"
    fi
  '';
  
  db-restore.exec = ''
    echo "🔄 Use 'devenv tasks run' for database operations"
    if [ -z "$1" ]; then
      echo "Usage: db-restore <backup_file>"
      exit 1
    fi
    if [ "$ENDO_API_MODE" = "production" ]; then
      echo "Production: psql -h <DB_HOST> -p <DB_PORT> -U <DB_USER> -d <DB_NAME> < $1"
    else
      echo "Development: Restore not typically needed for SQLite development"
    fi
  '';

  # Environment setup scripts
  env-pipe.exec = ''
    # Skip local config generation if local_settings.py exists (luxnix managed)
    if [ ! -f "local_settings.py" ]; then
      # Use unified management system instead of individual scripts
      echo "Setting up environment using unified management system..."
      manage setup
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

  gpu-check.exec = "${pkgs.uv}/bin/uv run python scripts/gpu-check.py";

  # Legacy scripts (deprecated - use setup_project.py instead)
  ensure-psql.exec = "${pkgs.uv}/bin/uv run python scripts/ensure_psql.py";
  env-fetch-db-pwd-file.exec = "${pkgs.uv}/bin/uv run python scripts/fetch_db_pwd_file.py";
  env-init-conf.exec = "${pkgs.uv}/bin/uv run python scripts/make_conf.py";
  env-build.exec = "${pkgs.uv}/bin/uv run env_setup.py";
  
  # Unified setup system - all functions moved to management.nix
  # These scripts were removed during cleanup but functionality preserved in 'manage' command
  
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
}
