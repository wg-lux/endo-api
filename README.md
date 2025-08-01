# endo-api
Basic Django Project using EndoReg-DB


## Submodules
To initilize the submodules run:
```
git submodule init
git submodule update
```


## Debug Nix Variables
```nix-repl
# Nix Vars
varsNix = import ./devenv/vars.nix
varsNix {
  dataDir = "data";
  confDir = "./conf";
  djangoModuleName = "endo_api";
  host = "localhost";
  port = "8118";
}

# Full Devenv Utils submodule
pkgs = import <nixpkgs> {}
defaultNix = import ./devenv/default.nix
defaultNix {
  pkgs = pkgs;
  djangoModuleName = "endo_api";
  host = "localhost";
  port = "8118";
  dataDir = "data";
  confDir = "./conf";
  uvPackage = pkgs.uv; 
}

```