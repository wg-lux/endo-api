#!/usr/bin/env python3
"""
Configuration Validation and Smoke Tests (Updated)

Quick validations for configuration and environment that do not require legacy tools.
"""

import json
import shutil
import subprocess
from pathlib import Path
import pytest


HAS_NIX = shutil.which("nix-instantiate") is not None


def test_nix_config_syntax():
    print("Testing app_config.nix and devenv.nix syntax...")
    if not HAS_NIX:
        pytest.skip("⏭️  nix-instantiate not available; skipping Nix syntax checks")
    for file in ["app_config.nix", "devenv.nix"]:
        result = subprocess.run(["nix-instantiate", "--parse", file], capture_output=True, text=True)
        assert result.returncode == 0, f"❌ Nix syntax error in {file}: {result.stderr}"
    print("✅ Nix syntax valid")


def test_config_values():
    print("Testing configuration value accessibility...")
    if not HAS_NIX:
        pytest.skip("⏭️  nix-instantiate not available; skipping config evaluation checks")
    test_paths = [
        ("app.name", "Application name"),
        ("app.djangoModule", "Django module"),
        ("server.host", "Server host"),
        ("server.port", "Server port"),
        ("server.protocol", "Server protocol"),
    ]
    for path, description in test_paths:
        result = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", path],
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"❌ Failed to read {description} ({path}): {result.stderr}"
        try:
            value = json.loads(result.stdout.strip())
            if not value:
                print(f"⚠️  Empty value for {description} ({path})")
        except json.JSONDecodeError:
            pytest.fail(f"❌ Invalid JSON for {description} ({path}): {result.stdout}")
    print("✅ Configuration values accessible")


def test_django_settings_imports():
    print("Testing Django settings imports...")
    from importlib import import_module
    try:
        import_module("endo_api.settings_dev")
        import_module("endo_api.settings_prod")
        print("✅ Django settings modules import successfully")
    except Exception as e:
        pytest.fail(f"❌ Failed to import settings: {e}")


def main():
    print("=" * 60)
    print("SMOKE TESTS")
    print("=" * 60)

    tests = [
        ("Nix Syntax", test_nix_config_syntax),
        ("Config Values", test_config_values),
        ("Django Settings Import", test_django_settings_imports),
    ]

    passed = 0
    failed = 0
    skipped = 0

    for name, fn in tests:
        print(f"\n--- {name} ---")
        try:
            fn()
            passed += 1
        except Exception as e:
            ename = e.__class__.__name__.lower()
            if 'skip' in ename:
                print(f"⚠️  Test {name} skipped: {e}")
                skipped += 1
            else:
                print(f"❌ Test crashed: {e}")
                failed += 1

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Passed: {passed}")
    print(f"Skipped: {skipped}")
    print(f"Failed: {failed}")
    print(f"Total:  {passed + failed + skipped}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
