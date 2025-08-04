"""
Central node settings for luxnix managed deployments.
This is used when CENTRAL_NODE=true environment variable is set.
"""
import os
# Import all production settings as base (Django pattern for settings files)
from .settings_prod import *  # noqa: F403,F401

# Override settings for central nodes
if os.environ.get("CENTRAL_NODE", "false").lower() == "true":
    print("Loading central node configuration")
    
    # Central nodes may have different CORS settings
    # These will be overridden by local_settings.py if present
    CORS_ALLOW_CREDENTIALS = True
    
    # Central nodes have access to additional endpoints
    # Add any central-node specific middleware or apps here
    
# Import luxnix local settings if available (for managed deployments)
# This will override any settings above with deployment-specific values
try:
    from local_settings import *  # noqa: F403,F401
    print("Loaded luxnix local_settings.py for central node")
except ImportError:
    print("No local_settings.py found - using default central node settings")
    # Import stub to satisfy linters in development
    try:
        from .local_settings_stub import *  # noqa: F403,F401
    except ImportError:
        pass
