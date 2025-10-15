"""Legacy settings namespace that forwards to the canonical ``endo_api`` modules.

Importing ``config.settings`` will default to the production configuration,
mirroring Django's convention of selecting the main deployment settings module.
"""

from .prod import *  # noqa: F401,F403
