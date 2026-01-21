from pathlib import Path
import os

# Import all base settings
from .settings_base import *  # noqa: F403,F401
from .settings_base.env import (
    require_secret_key,
    debug_default,
    allowed_hosts_default,
    csrf_trusted_origins_default,
    security_flags,
    db_config,
)

# ----------------------------------------------------------------------------
# Secrets and core settings from environment
# ----------------------------------------------------------------------------

# Must be set via environment variable in production for security
SECRET_KEY = require_secret_key()

# Debug and hosts
DEBUG = debug_default()
ALLOWED_HOSTS = allowed_hosts_default()
CSRF_TRUSTED_ORIGINS = csrf_trusted_origins_default()
if not DEBUG and "*" in ALLOWED_HOSTS:
    raise ValueError("ALLOWED_HOSTS must not contain '*' in production.")

# Security flags
_flags = security_flags()
SECURE_SSL_REDIRECT = _flags["SECURE_SSL_REDIRECT"]
SESSION_COOKIE_SECURE = _flags["SESSION_COOKIE_SECURE"]
CSRF_COOKIE_SECURE = _flags["CSRF_COOKIE_SECURE"]

# ----------------------------------------------------------------------------
# Database configuration
# Use centralized db_config() helper from settings_base.env
# ----------------------------------------------------------------------------

DATABASES = db_config()

# ----------------------------------------------------------------------------
# Staticfiles
# ----------------------------------------------------------------------------
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
