import os
import json
import base64
import tempfile
from urllib.parse import urlparse, unquote
from typing import Any, Dict, List


def _warn(msg: str) -> None:
    print(f"[env] {msg}")


def get_bool(key: str, default: bool = False) -> bool:
    val = os.environ.get(key)
    if val is None:
        return default
    return str(val).strip().lower() in {"1", "true", "yes", "on"}


def get_list(key: str, default: List[str] | None = None) -> List[str]:
    raw = os.environ.get(key)
    if not raw:
        return list(default or [])
    return [s.strip() for s in raw.split(",") if s.strip()]


def get_str(key: str, default: str | None = None) -> str | None:
    return os.environ.get(key, default)


def get_env_mode() -> str:
    # Canonical: DJANGO_ENV; legacy: ENDO_API_MODE
    mode = os.environ.get("DJANGO_ENV")
    if mode:
        mode = mode.strip().lower()
    if not mode:
        legacy = os.environ.get("ENDO_API_MODE")
        if legacy:
            _warn("ENDO_API_MODE is deprecated; use DJANGO_ENV")
            mode = legacy.strip().lower()
    if mode not in {"development", "production"}:
        mode = "development"
    return mode


def debug_default() -> bool:
    # DJANGO_DEBUG overrides; else derive from DJANGO_ENV
    if get_str("DJANGO_DEBUG") is not None:
        return get_bool("DJANGO_DEBUG", False)
    return get_env_mode() == "development"


def require_secret_key() -> str:
    sk = os.environ.get("DJANGO_SECRET_KEY")
    if not sk:
        raise ValueError("DJANGO_SECRET_KEY must be set in production")
    return sk


def dev_secret_key() -> str:
    return os.environ.get("DJANGO_SECRET_KEY", "dev-secret-key")


def allowed_hosts_default() -> List[str]:
    return get_list("DJANGO_ALLOWED_HOSTS", ["localhost", "127.0.0.1", "*"])


def csrf_trusted_origins_default() -> List[str]:
    return get_list("DJANGO_CSRF_TRUSTED_ORIGINS", [])


def security_flags() -> Dict[str, bool]:
    return {
        "SECURE_SSL_REDIRECT": get_bool("DJANGO_SECURE_SSL_REDIRECT", False) or get_bool("SECURE_SSL_REDIRECT", False),
        "SESSION_COOKIE_SECURE": get_bool("DJANGO_SESSION_COOKIE_SECURE", False) or get_bool("SESSION_COOKIE_SECURE", False),
        "CSRF_COOKIE_SECURE": get_bool("DJANGO_CSRF_COOKIE_SECURE", False) or get_bool("CSRF_COOKIE_SECURE", False),
    }


def _db_options_from_env() -> Dict[str, Any]:
    # JSON override takes precedence
    options_raw = os.environ.get("DJANGO_DB_OPTIONS")
    if options_raw:
        try:
            return json.loads(options_raw)
        except Exception as exc:  # noqa: BLE001
            raise ValueError("DJANGO_DB_OPTIONS must be valid JSON") from exc

    opts: Dict[str, Any] = {}

    sslmode = os.environ.get("DB_SSLMODE")
    if sslmode:
        opts["sslmode"] = sslmode

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


def _engine_from_scheme(scheme: str) -> str:
    s = (scheme or "").lower()
    if s in ("postgres", "postgresql", "psql", "postgresql+psycopg2"):
        return "django.db.backends.postgresql"
    if s in ("mysql", "mysql+pymysql"):
        return "django.db.backends.mysql"
    if s in ("sqlite", "sqlite3"):
        return "django.db.backends.sqlite3"
    return "django.db.backends.postgresql"


def db_config() -> Dict[str, Dict[str, Any]]:
    """Build a Django DATABASES setting from env.

    Rules:
    - Prefer DATABASE_URL
    - Else DB_ENGINE/DB_NAME/DB_USER/DB_PASSWORD/DB_HOST/DB_PORT
    - DB_CONFIG_FILE is removed; not supported.
    """
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

    return {
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
