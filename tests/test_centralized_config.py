#!/usr/bin/env python3
"""
Centralized configuration tests (updated for env-first).
"""

import json
import os
import subprocess
import unittest
import shutil
from pathlib import Path


PROJECT_ROOT = Path(__file__).parent.parent
HAS_NIX = shutil.which("nix-instantiate") is not None


@unittest.skipUnless(HAS_NIX, "nix-instantiate not available")
class TestCentralizedConfig(unittest.TestCase):
    def test_app_config_valid(self):
        result = subprocess.run(
            ["nix-instantiate", "--parse", str(PROJECT_ROOT / "app_config.nix")],
            capture_output=True, text=True, cwd=PROJECT_ROOT
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_values_accessible(self):
        for attr in ["app.name", "app.djangoModule", "server.host", "server.port", "server.protocol"]:
            with self.subTest(attr=attr):
                result = subprocess.run(
                    ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", attr],
                    capture_output=True, text=True, cwd=PROJECT_ROOT
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                json.loads(result.stdout.strip())

    def test_django_module_dir_exists(self):
        result = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "app.djangoModule"],
            capture_output=True, text=True, cwd=PROJECT_ROOT
        )
        self.assertEqual(result.returncode, 0)
        module = json.loads(result.stdout.strip())
        self.assertTrue((PROJECT_ROOT / module).exists())


@unittest.skipUnless(HAS_NIX, "nix-instantiate not available")
class TestDevEnvIntegration(unittest.TestCase):
    def test_devenv_nix_parse(self):
        result = subprocess.run(
            ["nix-instantiate", "--parse", str(PROJECT_ROOT / "devenv.nix")],
            capture_output=True, text=True, cwd=PROJECT_ROOT
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_scripts_reference_config(self):
        content = (PROJECT_ROOT / "devenv" / "scripts.nix").read_text()
        self.assertIn("appConfig", content)


@unittest.skipUnless(os.environ.get("DATABASE_URL") or os.environ.get("DB_NAME"), "DB not configured")
class TestOptionalDatabase(unittest.TestCase):
    def test_prod_settings_require_db(self):
        import importlib
        # Ensure SECRET_KEY is set to avoid failure for the wrong reason
        os.environ.setdefault("DJANGO_SECRET_KEY", "test")
        # Provide a minimal DB via env if not DATABASE_URL
        os.environ.setdefault("DB_ENGINE", "django.db.backends.sqlite3")
        os.environ.setdefault("DB_NAME", ":memory:")
        try:
            importlib.import_module("endo_api.settings_prod")
        except Exception as e:
            self.fail(f"Failed importing prod settings with provided DB env: {e}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
