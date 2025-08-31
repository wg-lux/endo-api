# Processes configuration for devenv
{ isDev ? false }:
{
  # Unified Django process that adapts to mode
  django = {
    exec = "run-server";
  };
}
