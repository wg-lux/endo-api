"""
Central node settings for managed deployments.
This is used when CENTRAL_NODE=true environment variable is set.
"""
import os
# Import all production settings as base
from .settings_prod import *  # noqa: F403,F401

# Override settings for central nodes
if os.environ.get("CENTRAL_NODE", "false").lower() == "true":
    print("Loading central node configuration")
    CORS_ALLOW_CREDENTIALS = True
    # Add central-node specific overrides here
