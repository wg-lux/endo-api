#!/usr/bin/env python3
"""
Unified Setup Script for Endo API
=================================

This script coordinates environment and configuration setup,
replacing the legacy env_setup.py and providing a single entry point
for project initialization.
"""

import sys
import os
from pathlib import Path

# Add scripts directory to Python path for imports
scripts_dir = Path(__file__).parent
sys.path.insert(0, str(scripts_dir))

try:
    from env_manager import EnvironmentManager
    from config_manager import ConfigurationManager
except ImportError as e:
    print(f"Failed to import required modules: {e}")
    print("Please ensure you're running this from the project root directory")
    sys.exit(1)


def setup_project():
    """
    Complete project setup including environment and configuration.
    """
    print("=" * 50)
    print("Endo API Project Setup")
    print("=" * 50)
    
    mode = os.environ.get("ENDO_API_MODE", "development")
    print(f"Current mode: {mode}")
    print()
    
    try:
        # Step 1: Environment Setup
        print("Step 1: Setting up environment...")
        env_manager = EnvironmentManager()
        env_manager.setup_environment()
        print("✓ Environment setup completed")
        print()
        
        # Step 2: Configuration Setup
        print("Step 2: Setting up configuration...")
        config_manager = ConfigurationManager()
        config_manager.setup_configuration()
        print("✓ Configuration setup completed")
        print()
        
        # Step 3: Validation
        print("Step 3: Validating setup...")
        if config_manager.validate_configuration():
            print("✓ Setup validation passed")
        else:
            print("✗ Setup validation failed")
            return False
        
        print()
        print("=" * 50)
        print("Project setup completed successfully!")
        print("=" * 50)
        print()
        print("Next steps:")
        print("1. Review the generated .env file and adjust settings as needed")
        print("2. If using production mode, update database credentials in conf/db_pwd")
        print("3. Run 'devenv shell' to enter the development environment")
        print("4. Use 'run-server' to start the application server")
        
        return True
        
    except Exception as e:
        print(f"✗ Setup failed: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point."""
    success = setup_project()
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
