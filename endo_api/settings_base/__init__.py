import os
from pathlib import Path

from endoreg_db.utils.paths import STORAGE_DIR
from endoreg_db.logger_conf import get_logging_config
X_FRAME_OPTIONS = "SAMEORIGIN"

from .env import debug_default  # new env helpers

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8000")

# Shared settings for dev and test
BASE_DIR = Path(__file__).parent.parent.parent

MEDIA_ROOT = STORAGE_DIR
MEDIA_URL = '/media/'

STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

STATIC_ROOT.mkdir(exist_ok = True)

endoreg_db_dir = Path(os.environ.get("ENDOREG_DB_DIR", "./libs/endoreg-db")).resolve()

ASSET_DIR = endoreg_db_dir / "tests/assets"
RUN_VIDEO_TESTS = os.environ.get("RUN_VIDEO_TESTS", "true").lower() == "true"

# DEBUG derived from env module (DJANGO_DEBUG or DJANGO_ENV)
DEBUG = debug_default()

# Base secret key remains lenient in base; prod enforces requirement
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "replace-this-with-a-secure-key")

# Django module name with safe default
MODULE_NAME = os.environ.get("DJANGO_MODULE", "endo_api")


FILE_LOG_LEVEL = os.environ.get("FILE_LOG_LEVEL", "DEBUG").upper()

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]


INSTALLED_APPS = [
    "modeltranslation",
    "endoreg_db.apps.EndoregDbConfig",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "django_extensions",
    "corsheaders",
]

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

TIME_ZONE = "Europe/Berlin"
ROOT_URLCONF = f"{MODULE_NAME}.urls"
LOGGER_NAMES = [
  "endo_api.asgi"
]

LOGGING = get_logging_config(LOGGER_NAMES, file_log_level=FILE_LOG_LEVEL)

# SECURE_SSL_REDIRECT = True
# SESSION_COOKIE_SECURE = True
# CSRF_COOKIE_SECURE = True
# SECURE_HSTS_SECONDS = 3600
# SECURE_HSTS_INCLUDE_SUBDOMAINS = True
# SECURE_HSTS_PRELOAD = True
# SECURE_BROWSER_XSS_FILTER = True
# SECURE_CONTENT_TYPE_NOSNIFF = True
