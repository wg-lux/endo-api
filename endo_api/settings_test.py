"""Settings used for automated test runs.

We start from the development configuration and allow environment variables to
adjust the database backend so CI jobs can point at a persistent SQLite file or
an external Postgres instance. The defaults mirror the values exposed in the
`.env` template (TEST_DB_* variables).
"""

from __future__ import annotations

import os
from pathlib import Path

from .settings_dev import *  # noqa: F401,F403

_engine = os.environ.get("TEST_DB_ENGINE")
_name = os.environ.get("TEST_DB_NAME")
_user = os.environ.get("TEST_DB_USER")
_password = os.environ.get("TEST_DB_PASSWORD")
_host = os.environ.get("TEST_DB_HOST")
_port = os.environ.get("TEST_DB_PORT")
_disable_migrations = os.environ.get("TEST_DISABLE_MIGRATIONS")

if _engine:
    DATABASES["default"]["ENGINE"] = _engine  # noqa: F405

if _name:
    test_db_path = Path(_name)
    if not test_db_path.is_absolute():
        test_db_path = Path(BASE_DIR) / test_db_path  # noqa: F405
    DATABASES["default"]["NAME"] = str(test_db_path)  # noqa: F405

if _user:
    DATABASES["default"]["USER"] = _user  # noqa: F405
if _password:
    DATABASES["default"]["PASSWORD"] = _password  # noqa: F405
if _host:
    DATABASES["default"]["HOST"] = _host  # noqa: F405
if _port:
    DATABASES["default"]["PORT"] = _port  # noqa: F405

# Ensure Django uses the same database for the testing alias
DATABASES["default"].setdefault("TEST", {})  # noqa: F405
DATABASES["default"]["TEST"].setdefault("NAME", DATABASES["default"]["NAME"])  # noqa: F405

if _disable_migrations and _disable_migrations.strip().lower() in {"1", "true", "yes", "on"}:
    MIGRATION_MODULES = {app: None for app in INSTALLED_APPS}  # noqa: F405
