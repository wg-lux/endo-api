from pathlib import Path
import os
from .settings_base import (
    INSTALLED_APPS,
    DEFAULT_AUTO_FIELD,
    TIME_ZONE,
    STATIC_URL,
    STATIC_ROOT,
    MEDIA_ROOT,
    MEDIA_URL,
    BASE_DIR,
    TEMPLATES,
    ROOT_URLCONF,
    MIDDLEWARE,
    LOGGING,
    BASE_URL,
    ASSET_DIR,
    RUN_VIDEO_TESTS,
    DEBUG,
    SECRET_KEY,
    # SECURE_SSL_REDIRECT, 
    # SESSION_COOKIE_SECURE, 
    # CSRF_COOKIE_SECURE, 
    # SECURE_HSTS_SECONDS, 
    # SECURE_HSTS_INCLUDE_SUBDOMAINS, 
    # SECURE_HSTS_PRELOAD, 
    # SECURE_BROWSER_XSS_FILTER, 
    # SECURE_CONTENT_TYPE_NOSNIFF, 
)

ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "*").split(",")

# Example PostgreSQL config (adjust as needed)
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'prod_sim_db.sqlite3',
    },
}

STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
# Disable HTTPS redirect for demonstration
SECURE_SSL_REDIRECT = False
# Optionally, also disable secure cookies for demo
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False
