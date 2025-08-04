import os
# Import all base settings (Django pattern for settings files)
from .settings_base import *  # noqa: F403,F401

# Development-specific overrides
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "*").split(",")

# Example PostgreSQL config (adjust as needed)
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'prod_sim_db.sqlite3',  # noqa: F405
    },
}

STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
# Disable HTTPS redirect for demonstration
SECURE_SSL_REDIRECT = False
# Optionally, also disable secure cookies for demo
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False

# Import luxnix local settings if available (for managed deployments)
try:
    from local_settings import *  # noqa: F403,F401
    print("Loaded luxnix local_settings.py")
except ImportError:
    print("No local_settings.py found - using default development settings")
    # Import stub to satisfy linters in development
    try:
        from .local_settings_stub import *  # noqa: F403,F401
    except ImportError:
        pass
