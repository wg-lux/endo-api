from pathlib import Path
import os
from endoreg_db.utils import DbConfig
from base_settings import (
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
    # SECURE_SSL_REDIRECT, 
    # SESSION_COOKIE_SECURE, 
    # CSRF_COOKIE_SECURE, 
    # SECURE_HSTS_SECONDS, 
    # SECURE_HSTS_INCLUDE_SUBDOMAINS, 
    # SECURE_HSTS_PRELOAD, 
    # SECURE_BROWSER_XSS_FILTER, 
    # SECURE_CONTENT_TYPE_NOSNIFF, 
)


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


ASSET_DIR = Path(__file__).parent / "tests/assets"
RUN_VIDEO_TESTS = os.environ.get("RUN_VIDEO_TESTS", "true").lower() == "true"

# Production settings
DEBUG = os.environ.get("DJANGO_DEBUG", "False")  # Changed from True to False for production
if DEBUG.lower() == "true":
    DEBUG = True
else:
    DEBUG = False

# It's best to set this via environment variable in production
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "replace-this-with-a-secure-key")

#TODO in a real production project, you would set this to a list of your domain names
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "*").split(",")

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

# Disable HTTPS redirect for demonstration
SECURE_SSL_REDIRECT = False
# Optionally, also disable secure cookies for demo
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False
