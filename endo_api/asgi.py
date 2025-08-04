"""
ASGI config for endo_api project.

It exposes the ASGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/5.2/howto/deployment/asgi/
"""

import os
import logging
from django.core.asgi import get_asgi_application

logger = logging.getLogger(__name__)


_settings_module = os.environ.get('DJANGO_SETTINGS_MODULE',)
assert _settings_module, "DJANGO_SETTINGS_MODULE environment variable is not set."
logger.info(f"Using settings module: {_settings_module}")


application = get_asgi_application()
