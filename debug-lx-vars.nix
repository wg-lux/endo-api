(import ./devenv/vars.nix {
  dataDir = "data";
  confDir = "./conf";
  djangoModuleName = "endo_api";
  host = "localhost";
  port = "8118";
})

# nix eval --impure --expr 'import ./debug-lx-vars.nix' --json | jq