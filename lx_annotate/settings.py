# Temporary compatibility shim - redirects to proper endo_api settings
import os
mode = os.environ.get("ENDO_API_MODE", "development")

if mode == "production":
    from endo_api.settings_prod import *  # noqa: F403,F401
else:
    from endo_api.settings_dev import *  # noqa: F403,F401
