{
  pkgs ? import <nixpkgs> {},
}:

pkgs.mkShell {
  buildInputs = [
    (import ./devenv/default.nix {
      inherit pkgs;
      lib = pkgs.lib;
      appConfig = import ./app_config.nix;
      djangoModuleName = "endo_api";
      host = "localhost";
      port = "8118";
      base_url = "http://localhost:8118";
      dataDir = "./data";
      confDir = "./conf";
      confTemplateDir = "./conf_template";
      homeDir = builtins.getEnv "HOME";
      uvPackage = pkgs.uv;
      isDev = true;
    }).buildInputs
  ];
}
