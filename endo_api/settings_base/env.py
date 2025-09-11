import os
import json
import base64
import tempfile
from urllib.parse import urlparse, unquote
from typing import Any, Dict, List
from pathlib import Path


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
    return get_list("DJANGO_ALLOWED_HOSTS", ["localhost", "127.0.0.1", "10.0.0.0/8", "172.16.255.0/24"])


def csrf_trusted_origins_default() -> List[str]:
    return get_list("DJANGO_CSRF_TRUSTED_ORIGINS", [])


def security_flags() -> Dict[str, bool]:
    return {
        "SECURE_SSL_REDIRECT": get_bool("DJANGO_SECURE_SSL_REDIRECT", False) or get_bool("SECURE_SSL_REDIRECT", False),
        "SESSION_COOKIE_SECURE": get_bool("DJANGO_SESSION_COOKIE_SECURE", False) or get_bool("SESSION_COOKIE_SECURE", False),
        "CSRF_COOKIE_SECURE": get_bool("DJANGO_CSRF_COOKIE_SECURE", False) or get_bool("CSRF_COOKIE_SECURE", False),
    }


def _db_options_from_env(engine: str, url_opts: dict | None = None) -> Dict[str, Any]:
    """Build DB driver options from environment, JSON override, and URL query options.

    Priority (highest -> lowest):
      1. DJANGO_DB_OPTIONS (JSON) - explicit override
      2. Environment-derived values (DB_SSLMODE, DB_SSLROOTCERT, DB_SSLCERT, DB_SSLKEY or their _B64 variants)
      3. Options parsed from the DATABASE_URL query string (url_opts)

    The returned keys are engine-aware. For Postgres we emit libpq-style keys
    (sslmode, sslrootcert, sslcert, sslkey, options, target_session_attrs).
    For MySQL we place TLS material under a top-level 'ssl' dict with keys
    'ca','cert','key' (and other MySQL-specific params preserved).
    """
    # JSON override takes precedence; parse but keep as base to merge env/file values
    options_raw = os.environ.get("DJANGO_DB_OPTIONS")
    if options_raw:
        try:
            try:
                json_opts = json.loads(options_raw)
            except Exception as exc:  # noqa: BLE001
                raise ValueError("DJANGO_DB_OPTIONS must be valid JSON") from exc
        except Exception:
            # If JSON parsing fails upstream, propagate useful error
            raise
    else:
        json_opts = {}

    # start from JSON-provided options
    opts: Dict[str, Any] = dict(json_opts or {})

    # Env-level simple override
    sslmode = os.environ.get("DB_SSLMODE")
    if sslmode:
        if engine.startswith("django.db.backends.postgresql"):
            opts.setdefault("sslmode", sslmode)
        else:
            # MySQL uses ssl options under 'ssl' dict
            if "ssl" not in opts:
                opts["ssl"] = {}
            opts["ssl"].setdefault("mode", sslmode)

    def _maybe_write_b64(env_key: str, suffix: str) -> str | None:
        b64_val = os.environ.get(env_key)
        if not b64_val:
            return None
        data = base64.b64decode(b64_val)
        fd, path = tempfile.mkstemp(prefix="db_", suffix=suffix)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return path

    # Files from explicit env vars or b64 variants
    rootcert = os.environ.get("DB_SSLROOTCERT") or _maybe_write_b64("DB_SSLROOTCERT_B64", ".crt")
    cert = os.environ.get("DB_SSLCERT") or _maybe_write_b64("DB_SSLCERT_B64", ".crt")
    key = os.environ.get("DB_SSLKEY") or _maybe_write_b64("DB_SSLKEY_B64", ".key")

    if engine.startswith("django.db.backends.postgresql"):
        if rootcert:
            opts.setdefault("sslrootcert", rootcert)
        if cert:
            opts.setdefault("sslcert", cert)
        if key:
            opts.setdefault("sslkey", key)
    else:
        # MySQL: place TLS materials under ssl dict
        if rootcert or cert or key:
            if "ssl" not in opts:
                opts["ssl"] = {}
            if rootcert:
                opts["ssl"].setdefault("ca", rootcert)
            if cert:
                opts["ssl"].setdefault("cert", cert)
            if key:
                opts["ssl"].setdefault("key", key)

    # Merge URL-derived options (lowest priority) only where not already set
    if url_opts:
        if engine.startswith("django.db.backends.postgresql"):
            for k in ("sslmode", "sslrootcert", "sslcert", "sslkey", "options", "target_session_attrs"):
                v = url_opts.get(k)
                if v is not None and k not in opts:
                    opts[k] = v
        elif engine.startswith("django.db.backends.mysql"):
            # url_opts may contain 'ssl' dict or top-level mysql params
            u_ssl = url_opts.get("ssl") if isinstance(url_opts.get("ssl"), dict) else {}
            if u_ssl:
                if "ssl" not in opts:
                    opts["ssl"] = {}
                for subk, subv in u_ssl.items():
                    if subk not in opts["ssl"]:
                        opts["ssl"][subk] = subv
            for k, v in url_opts.items():
                if k == "ssl":
                    continue
                if k not in opts:
                    opts[k] = v
        else:
            # default: shallow merge for unknown engines
            for k, v in url_opts.items():
                opts.setdefault(k, v)

    return opts


def _parse_db_url_query_options(query: str, engine: str) -> Dict[str, Any]:
    """Parse DATABASE_URL query string into engine-aware option dict.

    - For Postgres: return libpq-style keys where applicable.
    - For MySQL: return a dict with a top-level 'ssl' mapping for TLS files.
    """
    from urllib.parse import parse_qs

    if not query:
        return {}
    qs = parse_qs(query, keep_blank_values=True)

    # helper to pick first value
    def _first(key: str):
        return qs.get(key, [None])[-1]

    if engine.startswith("django.db.backends.postgresql"):
        allowed = {
            "sslmode",
            "sslrootcert",
            "sslcert",
            "sslkey",
            "options",
            "target_session_attrs",
        }
        out: Dict[str, Any] = {}
        for k in allowed:
            v = _first(k)
            if v is not None:
                out[k] = v
        return out

    if engine.startswith("django.db.backends.mysql"):
        # common mappings for MySQL DSNs
        ssl_mapping = {
            "ssl-ca": "ca",
            "ssl-cert": "cert",
            "ssl-key": "key",
            "ssl-mode": "mode",
        }
        out: Dict[str, Any] = {}
        ssl: Dict[str, Any] = {}
        for qk, dest in ssl_mapping.items():
            v = _first(qk)
            if v is not None:
                ssl[dest] = v
        if ssl:
            out["ssl"] = ssl
        # preserve other common params
        for k in ("charset", "collation"):
            v = _first(k)
            if v is not None:
                out[k] = v
        return out

    return {}


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

    DB_CONFIG_FILE support has been removed; provide DATABASE_URL or DB_* env vars.
    """
    db_from_url = os.environ.get("DATABASE_URL")
    url_opts = None
    if db_from_url:
        parsed = urlparse(db_from_url)
        db_name = parsed.path.lstrip("/") or os.environ.get("DB_NAME")
        db_user = unquote(parsed.username) if parsed.username else os.environ.get("DB_USER")
        db_password = unquote(parsed.password) if parsed.password else os.environ.get("DB_PASSWORD")
        db_host = parsed.hostname or os.environ.get("DB_HOST")
        db_port = str(parsed.port) if parsed.port else os.environ.get("DB_PORT")
        db_engine = _engine_from_scheme(parsed.scheme)
        # parse query options engine-aware
        url_opts = _parse_db_url_query_options(parsed.query, db_engine)
    elif os.environ.get("DB_NAME"):
        db_engine = os.environ.get("DB_ENGINE", "django.db.backends.postgresql")
        db_name = os.environ.get("DB_NAME")
        db_user = os.environ.get("DB_USER")
        db_password = os.environ.get("DB_PASSWORD")
        db_host = os.environ.get("DB_HOST", "localhost")
        db_port = os.environ.get("DB_PORT", "5432")
        url_opts = None
    else:
        raise ValueError(
            "Database configuration missing. Provide DATABASE_URL or DB_* environment variables."
        )

    return {
        "default": {
            "ENGINE": db_engine,
            "NAME": db_name,
            "USER": db_user,
            "PASSWORD": db_password,
            "HOST": db_host,
            "PORT": db_port,
            "OPTIONS": _db_options_from_env(db_engine, url_opts) or {},
        }
    }
