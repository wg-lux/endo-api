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

## Notes for default deployment
If we use a system configured with luxnix (https://github.com/wg-lux/luxnix), we need to run the "ensure-psql" script defined in 'devenv.nix'.
This will create the local PostGres Db (EndoRegDbLocal and ensures we have set the password defined in 'conf/db_pwd'; in future this will be automated, currently I am sadly forced to prioritize).

In its current state the default deployment on a fresh luxnix system needs following steps:
- first rebuild after activating the endo-api service will need some time as lots of dependencies are build
- check with 'sudo journalctl -xeu endo-api-boot' (doesnt auto update, close and re-open for updates)
- will most likely fail due to initially missing .env file (is actually created but most likely some timing issue causes failure)
- Restart Service should make it run
- Make sure to update the db_pwd file (by default, we expect it at '~/secrets/vault/SCRT_local_password_maintenance_password')
