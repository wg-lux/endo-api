# Environment configuration for devenv
{ lxVars, buildInputs, pkgs, lib, isDev ? false, appConfig }:
let
  # Add database-specific environment variables using centralized config
  # Secrets are read from environment variables, not baked into Nix store
  dbVars = if isDev then {
    # SQLite configuration for development (no password needed)
    DATABASE_ENGINE = appConfig.database.dev.engine;
    DATABASE_NAME = appConfig.database.dev.name;
    DATABASE_HOST = appConfig.database.dev.host;
    DATABASE_PORT = appConfig.database.dev.port;
    DATABASE_USER = appConfig.database.dev.user;
    # SQLite doesn't need password, but read from env if provided
    DATABASE_PASSWORD = ""; # Always empty for SQLite
  } else {
    # PostgreSQL configuration for production
    # Secrets must come from environment variables or external files
    DATABASE_ENGINE = appConfig.database.prod.engine;
    DATABASE_HOST = appConfig.database.prod.host;
    DATABASE_PORT = appConfig.database.prod.port;
    DATABASE_NAME = appConfig.database.prod.name;
    DATABASE_USER = appConfig.database.prod.user;
    # Password will be read from environment variable at runtime
    # Never bake secrets into Nix store!
    DATABASE_PASSWORD = ""; # Will be set via environment variable
  };

in
{
  LD_LIBRARY_PATH = "${
    with pkgs;
    lib.makeLibraryPath buildInputs
  }:/run/opengl-driver/lib:/run/opengl-driver-32/lib";
  
  # Mode indicator - export the environment variable
  ENDO_API_MODE = if isDev then "development" else "production";
  
  # Database configuration
  DATABASE_ENGINE = dbVars.DATABASE_ENGINE;
  DATABASE_NAME = dbVars.DATABASE_NAME;
  DATABASE_HOST = dbVars.DATABASE_HOST;
  DATABASE_PORT = builtins.toString dbVars.DATABASE_PORT;  # Ensure port is always a string
  DATABASE_USER = dbVars.DATABASE_USER;

} // lxVars
  # Conditionally include DATABASE_PASSWORD only when it's not empty
  // (lib.optionalAttrs (dbVars.DATABASE_PASSWORD != "" && dbVars.DATABASE_PASSWORD != null) {
    DATABASE_PASSWORD = dbVars.DATABASE_PASSWORD;
  })
