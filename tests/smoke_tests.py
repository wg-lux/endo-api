#!/usr/bin/env python3
"""
Configuration Validation and Smoke Tests (Updated)

Quick validations for configuration and environment that do not require legacy tools.
"""

import json
import shutil
import subprocess
from pathlib import Path


HAS_NIX = shutil.which("nix-instantiate") is not None


def test_nix_config_syntax():
    print("Testing app_config.nix and devenv.nix syntax...")
    if not HAS_NIX:
        print("⏭️  nix-instantiate not available; skipping Nix syntax checks")
        return True
    for file in ["app_config.nix", "devenv.nix"]:
        result = subprocess.run(["nix-instantiate", "--parse", file], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ Nix syntax error in {file}: {result.stderr}")
            return False
    print("✅ Nix syntax valid")
    return True


def test_config_values():
    print("Testing configuration value accessibility...")
    if not HAS_NIX:
        print("⏭️  nix-instantiate not available; skipping config evaluation checks")
        return True
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
        if result.returncode != 0:
            print(f"❌ Failed to read {description} ({path}): {result.stderr}")
            return False
        try:
            value = json.loads(result.stdout.strip())
            if not value:
                print(f"⚠️  Empty value for {description} ({path})")
        except json.JSONDecodeError:
            print(f"❌ Invalid JSON for {description} ({path}): {result.stdout}")
            return False
    print("✅ Configuration values accessible")
    return True


def test_django_settings_imports():
    print("Testing Django settings imports...")
    from importlib import import_module
    try:
        import_module("endo_api.settings_dev")
        import_module("endo_api.settings_prod")
        print("✅ Django settings modules import successfully")
        return True
    except Exception as e:
        print(f"❌ Failed to import settings: {e}")
        return False


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

    for name, fn in tests:
        print(f"\n--- {name} ---")
        try:
            if fn():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ Test crashed: {e}")
            failed += 1

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Total:  {passed + failed}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
