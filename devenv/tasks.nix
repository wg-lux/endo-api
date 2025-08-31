# Legacy Tasks Configuration (DEPRECATED)
# =======================================
# 
# This file contains legacy task definitions for backward compatibility.
# New functionality should be added to management.nix instead.
# 
# Most tasks have been moved to management.nix for unified management.
# This file will be removed in a future version.
{ pkgs }:
{
  "env:fetch-db-pwd-file" = {
    description = "Fetch the database password file";
    exec = "${pkgs.uv}/bin/uv run python scripts/fetch_db_pwd_file.py";
  };
  
  "env:init-conf" = {
    description = "Initialize configuration files";
    exec = "${pkgs.uv}/bin/uv run python scripts/make_conf.py";
  };
  
  "env:build" = {
    description = "Build the .env file";
    after = ["env:init-conf"];
    exec = "uv run env_setup.py";
  };

  # CUDA setup moved to management.nix to avoid duplication

  # Database operations moved to management.nix for unified task management
}
