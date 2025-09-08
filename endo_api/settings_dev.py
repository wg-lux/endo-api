import os
# Import all base settings (Django pattern for settings files)
from .settings_base import *  # noqa: F403,F401
from .settings_base.env import allowed_hosts_default, debug_default

# Development-specific overrides
DEBUG = debug_default()
ALLOWED_HOSTS = allowed_hosts_default()

# SQLite by default for development
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'prod_sim_db.sqlite3',  # noqa: F405
    },
}

STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
# Disable HTTPS redirect for dev
SECURE_SSL_REDIRECT = False
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False
