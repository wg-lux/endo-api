# Environment configuration for devenv
{ lxVars, buildInputs, pkgs, lib, isDev ? false, appConfig }:
let
  # Add database-specific environment variables using centralized config
  dbVars = if isDev then {
    # SQLite configuration for development
    DATABASE_ENGINE = appConfig.database.dev.engine;
    DATABASE_NAME = appConfig.database.dev.name;
    DATABASE_HOST = appConfig.database.dev.host;
    DATABASE_PORT = appConfig.database.dev.port;
    DATABASE_USER = appConfig.database.dev.user;
    DATABASE_PASSWORD = appConfig.database.dev.password;
  } else {
    # PostgreSQL configuration for production (expects external DB)
    # These will be overridden by actual environment variables in production
    DATABASE_ENGINE = appConfig.database.prod.engine;
    DATABASE_HOST = appConfig.database.prod.host;
    DATABASE_PORT = appConfig.database.prod.port;
    DATABASE_NAME = appConfig.database.prod.name;
    DATABASE_USER = appConfig.database.prod.user;
    DATABASE_PASSWORD = ""; # Set via environment or secrets
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
  DATABASE_PORT = dbVars.DATABASE_PORT;
  DATABASE_USER = dbVars.DATABASE_USER;
  DATABASE_PASSWORD = dbVars.DATABASE_PASSWORD;

} // lxVars
