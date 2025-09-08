# Environment configuration for devenv
{ lxVars, buildInputs, pkgs, lib, isDev ? false, appConfig }:
{
  LD_LIBRARY_PATH = "${
    with pkgs;
    lib.makeLibraryPath buildInputs
  }:/run/opengl-driver/lib:/run/opengl-driver-32/lib";
}
// lxVars
