# nix file importing devenv files
{ 
  pkgs,
  lib,
  appConfig,  # Centralized application configuration
  djangoModuleName, 
  host, 
  port, 
  base_url,
  dataDir,
  confDir, 
  confTemplateDir,
  uvPackage,
  isDev ? false,
}:
let
  # import lx_vars from vars.nix
  lx_vars = import ./vars.nix {
    dataDir = dataDir;
    confDir = confDir;
    confTemplateDir = confTemplateDir;
    djangoModuleName = djangoModuleName;
    host = host;
    port = port;
    base_url = base_url;
  };
  
  # import build inputs from build_inputs.nix
  buildInputs = import ./build_inputs.nix { inherit pkgs; };
  runtimePackages = import ./runtime_packages.nix { inherit pkgs uvPackage; };
  
  # import modular configurations
  scripts = import ./scripts.nix { 
    inherit pkgs djangoModuleName host port isDev appConfig; 
  };
  
  services = import ./services.nix { 
    inherit isDev appConfig; 
  };
  
  tasks = import ./tasks.nix { 
    inherit pkgs; 
  };
  
  processes = import ./processes.nix { 
    inherit isDev; 
  };
  
  containers = import ./containers.nix { appConfig = appConfig; };
  
  environment = import ./environment.nix { 
    lxVars = lx_vars;
    inherit buildInputs pkgs lib isDev appConfig;
  };

  # Import centralized management system
  managementSystem = import ./management.nix { inherit pkgs appConfig isDev; };

in 
{
  lx_vars = lx_vars;
  buildInputs = buildInputs;
  runtimePackages = runtimePackages;
  
  # Integrate centralized management with legacy modular components
  # Priority: management.nix tasks override legacy tasks.nix
  scripts = scripts // managementSystem.scripts;
  tasks = managementSystem.tasks // tasks;  # management.nix takes priority
  
  services = services;
  processes = processes;
  containers = containers;
  environment = environment;
}