#!/usr/bin/env python3
"""
Configuration Validation and Smoke Tests

This script provides quick validation tests for the centralized configuration system
without requiring full unittest setup. Useful for CI/CD and quick validation.
"""

import os
import sys
import json
import subprocess
from pathlib import Path


def test_nix_config_syntax():
    """Test that app_config.nix has valid Nix syntax."""
    print("Testing app_config.nix syntax...")
    
    result = subprocess.run(
        ["nix-instantiate", "--parse", "app_config.nix"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ Nix syntax error: {result.stderr}")
        return False
    
    print("✅ app_config.nix has valid Nix syntax")
    return True


def test_config_values():
    """Test that all expected configuration values are accessible."""
    print("Testing configuration value accessibility...")
    
    test_paths = [
        ("app.name", "Application name"),
        ("app.djangoModule", "Django module"),
        ("server.host", "Server host"),
        ("server.port", "Server port"),
        ("server.protocol", "Server protocol"),
        ("database.dev.engine", "Dev database engine"),
        ("database.prod.engine", "Prod database engine")
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
            else:
                print(f"✅ {description}: {value}")
        except json.JSONDecodeError:
            print(f"❌ Invalid JSON for {description} ({path}): {result.stdout}")
            return False
    
    return True


def test_config_manager_script():
    """Test that config-manager.sh is functional."""
    print("Testing config-manager.sh...")
    
    config_manager = Path("config-manager.sh")
    
    if not config_manager.exists():
        print("❌ config-manager.sh not found")
        return False
    
    if not os.access(config_manager, os.X_OK):
        print("❌ config-manager.sh is not executable")
        return False
    
    # Test show-config
    result = subprocess.run(
        ["./config-manager.sh", "show-config"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ show-config failed: {result.stderr}")
        return False
    
    output = result.stdout
    required_fields = ["Application Name:", "Django Module:", "Server Host:", "Server Port:"]
    
    for field in required_fields:
        if field not in output:
            print(f"❌ Missing field in output: {field}")
            return False
    
    print("✅ config-manager.sh is functional")
    return True


def test_devenv_integration():
    """Test that DevEnv can load the configuration."""
    print("Testing DevEnv integration...")
    
    # Test that devenv.nix syntax is valid
    result = subprocess.run(
        ["nix-instantiate", "--parse", "devenv.nix"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ devenv.nix syntax error: {result.stderr}")
        return False
    
    print("✅ devenv.nix syntax is valid")
    
    # Test that devenv can evaluate (without building)
    result = subprocess.run(
        ["nix-instantiate", "--eval", "devenv.nix"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ devenv.nix evaluation failed: {result.stderr}")
        return False
    
    print("✅ devenv.nix can be evaluated successfully")
    return True


def test_environment_manager():
    """Test environment manager functionality."""
    print("Testing environment manager...")
    
    env_manager = Path("scripts/env_manager.py")
    
    if not env_manager.exists():
        print("❌ scripts/env_manager.py not found")
        return False
    
    # Test that it can run without errors
    result = subprocess.run(
        ["python3", str(env_manager), "--help"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ env_manager.py failed: {result.stderr}")
        return False
    
    print("✅ env_manager.py is functional")
    return True


def test_configuration_consistency():
    """Test that configuration values are consistent across components."""
    print("Testing configuration consistency...")
    
    # Get port from config
    result = subprocess.run(
        ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "server.port"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ Failed to read port from config: {result.stderr}")
        return False
    
    config_port = json.loads(result.stdout.strip())
    
    # Get Django module from config  
    result = subprocess.run(
        ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "app.djangoModule"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"❌ Failed to read Django module from config: {result.stderr}")
        return False
    
    django_module = json.loads(result.stdout.strip())
    
    # Check that Django module directory exists
    django_path = Path(django_module)
    if not django_path.exists():
        print(f"❌ Django module directory {django_module} does not exist")
        return False
    
    print(f"✅ Configuration consistent - Port: {config_port}, Django module: {django_module}")
    return True


def test_documentation():
    """Test that documentation is comprehensive."""
    print("Testing documentation...")
    
    guide_path = Path("NATIVE_DEVENV_CONTAINERS_GUIDE.md")
    
    if not guide_path.exists():
        print("❌ NATIVE_DEVENV_CONTAINERS_GUIDE.md not found")
        return False
    
    with open(guide_path, 'r') as f:
        content = f.read()
    
    required_sections = [
        "Centralized Configuration",
        "app_config.nix", 
        "config-manager.sh",
        "set-port"
    ]
    
    for section in required_sections:
        if section not in content:
            print(f"❌ Documentation missing section: {section}")
            return False
    
    print("✅ Documentation is comprehensive")
    return True


def main():
    """Run all smoke tests."""
    print("=" * 60)
    print("CENTRALIZED CONFIGURATION SMOKE TESTS")
    print("=" * 60)
    
    tests = [
        ("Nix Configuration Syntax", test_nix_config_syntax),
        ("Configuration Values", test_config_values),
        ("Config Manager Script", test_config_manager_script),
        ("DevEnv Integration", test_devenv_integration),
        ("Environment Manager", test_environment_manager),
        ("Configuration Consistency", test_configuration_consistency),
        ("Documentation", test_documentation)
    ]
    
    passed = 0
    failed = 0
    
    for test_name, test_func in tests:
        print(f"\n--- {test_name} ---")
        try:
            if test_func():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ Test {test_name} crashed: {e}")
            failed += 1
    
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Total:  {passed + failed}")
    
    if failed == 0:
        print("🎉 ALL SMOKE TESTS PASSED!")
        return 0
    else:
        print("❌ Some tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
