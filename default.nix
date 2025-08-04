{
  pkgs ? import <nixpkgs> {},
}:

pkgs.mkShell {
  buildInputs = [
    (import ./devenv/default.nix {
      inherit pkgs;
      djangoModuleName = "endo_api";
      host = "localhost";
      port = "8118";
      base_url = "http://localhost:8118";
      dataDir = "./data";
      confDir = "./conf";
      confTemplateDir = "./conf_template";
      uvPackage = pkgs.uv;
    }).buildInputs
  ];
}
