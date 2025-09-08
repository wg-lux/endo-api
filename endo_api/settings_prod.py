from pathlib import Path
import os
from urllib.parse import urlparse, unquote
import json
import base64
import tempfile

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

# Security flags
_flags = security_flags()
SECURE_SSL_REDIRECT = _flags["SECURE_SSL_REDIRECT"]
SESSION_COOKIE_SECURE = _flags["SESSION_COOKIE_SECURE"]
CSRF_COOKIE_SECURE = _flags["CSRF_COOKIE_SECURE"]

# ----------------------------------------------------------------------------
# Database configuration
# Priority: DATABASE_URL > explicit DB_* env vars > DB_CONFIG_FILE (file)
# ----------------------------------------------------------------------------

def _engine_from_scheme(scheme: str) -> str:
    s = (scheme or "").lower()
    if s in ("postgres", "postgresql", "psql", "postgresql+psycopg2"):
        return "django.db.backends.postgresql"
    if s in ("mysql", "mysql+pymysql"):
        return "django.db.backends.mysql"
    if s in ("sqlite", "sqlite3"):
        return "django.db.backends.sqlite3"
    # Default to Postgres
    return "django.db.backends.postgresql"


def _db_options_from_env() -> dict:
    # JSON override takes precedence
    options_raw = os.environ.get("DJANGO_DB_OPTIONS")
    if options_raw:
        try:
            return json.loads(options_raw)
        except Exception:
            raise ValueError("DJANGO_DB_OPTIONS must be valid JSON when set")

    opts: dict[str, str] = {}

    # Common SSL options (psycopg)
    sslmode = os.environ.get("DB_SSLMODE")
    if sslmode:
        opts["sslmode"] = sslmode

    # Support base64-encoded certs/keys (avoid mounting files)
    def _maybe_write_b64(env_key: str, suffix: str) -> str | None:
        b64_val = os.environ.get(env_key)
        if not b64_val:
            return None
        data = base64.b64decode(b64_val)
        fd, path = tempfile.mkstemp(prefix="db_", suffix=suffix)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return path

    rootcert = os.environ.get("DB_SSLROOTCERT") or _maybe_write_b64("DB_SSLROOTCERT_B64", ".crt")
    cert = os.environ.get("DB_SSLCERT") or _maybe_write_b64("DB_SSLCERT_B64", ".crt")
    key = os.environ.get("DB_SSLKEY") or _maybe_write_b64("DB_SSLKEY_B64", ".key")

    if rootcert:
        opts["sslrootcert"] = rootcert
    if cert:
        opts["sslcert"] = cert
    if key:
        opts["sslkey"] = key

    return opts


db_from_url = os.environ.get("DATABASE_URL")
if db_from_url:
    parsed = urlparse(db_from_url)
    db_name = parsed.path.lstrip("/") or os.environ.get("DB_NAME")
    db_user = unquote(parsed.username) if parsed.username else os.environ.get("DB_USER")
    db_password = unquote(parsed.password) if parsed.password else os.environ.get("DB_PASSWORD")
    db_host = parsed.hostname or os.environ.get("DB_HOST")
    db_port = str(parsed.port) if parsed.port else os.environ.get("DB_PORT")
    db_engine = _engine_from_scheme(parsed.scheme)

elif os.environ.get("DB_NAME"):
    # Explicit variables
    db_engine = os.environ.get("DB_ENGINE", "django.db.backends.postgresql")
    db_name = os.environ.get("DB_NAME")
    db_user = os.environ.get("DB_USER")
    db_password = os.environ.get("DB_PASSWORD")
    db_host = os.environ.get("DB_HOST", "localhost")
    db_port = os.environ.get("DB_PORT", "5432")

else:
    raise ValueError(
        "Database configuration missing. Provide DATABASE_URL or DB_* env vars."
    )

DATABASES = {
    "default": {
        "ENGINE": db_engine,
        "NAME": db_name,
        "USER": db_user,
        "PASSWORD": db_password,
        "HOST": db_host,
        "PORT": db_port,
        "OPTIONS": _db_options_from_env() or {},
    }
}

# ----------------------------------------------------------------------------
# Staticfiles
# ----------------------------------------------------------------------------
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
