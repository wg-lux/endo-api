# DevEnv Container Configuration 
# =============================
# This file configures native DevEnv containers (not Docker containers)
# Following DevEnv best practices for container generation
{ pkgs, lib, appConfig }:
{
  # Development container - includes full development environment
  # Equivalent to running "devenv shell" but in container form
  "dev" = {
    name = "endo-api-dev";
    startupCommand = "run-server-container";
    # Include repo in container root so scripts exist without mounting
    copyToRoot = ./.;
  };

  # Production container - optimized runtime with minimal dependencies  
  # Focuses on running the application efficiently
  "prod" = {
    name = "endo-api-prod";
    startupCommand = "run-server-container";
    copyToRoot = ./.;
  };

  # Processes container - for running background processes
  # Equivalent to running "devenv up" but in container form
  "processes" = {
    name = "endo-api-processes";
    startupCommand = "run-server";
    copyToRoot = ./.;
  };
}
