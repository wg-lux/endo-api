# Container configuration for devenv
{ appConfig }:
{
  "${appConfig.containers.devImage}" = {
    name = appConfig.containers.devImage;
    startupCommand = "run-server-container";
  };

  "${appConfig.containers.prodImage}" = {
    name = appConfig.containers.prodImage;
    startupCommand = "run-server-container";
  };
}
