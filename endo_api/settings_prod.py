from pathlib import Path
import os
from endoreg_db.utils import DbConfig
# Import all base settings (Django pattern for settings files)
from .settings_base import *  # noqa: F403,F401


db_config_file = os.environ.get("DB_CONFIG_FILE")
if not db_config_file:
    raise ValueError("DB_CONFIG_FILE environment variable is not set")

assert isinstance(db_config_file, str), "DB_CONFIG_FILE must be a string path"


db_config_file = Path(db_config_file).resolve()

assert db_config_file.exists(), f"Database config file {db_config_file} does not exist"

db_cfg = DbConfig.from_file(db_config_file)

db_user = db_cfg.user
db_password = db_cfg.password
db_host = db_cfg.host
db_port = db_cfg.port
db_name = db_cfg.name


ASSET_DIR = Path(__file__).parent / "tests/assets"  # noqa: F405
RUN_VIDEO_TESTS = os.environ.get("RUN_VIDEO_TESTS", "true").lower() == "true"

# Production settings
DEBUG = os.environ.get("DJANGO_DEBUG", "False").lower() == "true"

# Must be set via environment variable in production for security
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY")

#TODO in a real production project, you would set this to a list of your domain names
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

# Example PostgreSQL config (adjust as needed)
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': db_name,
        'USER': db_user,
        'PASSWORD': db_password,
        'HOST': db_host,
        'PORT': db_port,
    }

}

STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

# Disabled for local deployment, change to fetch from environment in production
#TODO
SECURE_SSL_REDIRECT = False
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False

# Import luxnix local settings if available (for managed deployments)
# This will override the above settings with production values
try:
    from local_settings import *  # noqa: F403,F401
    print("Loaded luxnix local_settings.py for production")
except ImportError:
    print("No local_settings.py found - using default production settings")
    # Import stub to satisfy linters in development
    try:
        from .local_settings_stub import *  # noqa: F403,F401
    except ImportError:
        pass
