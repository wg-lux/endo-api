#!/usr/bin/env python3
"""
Configuration Manager for Endo API
==================================

This module provides improved configuration management,
replacing the legacy make_conf.py with better mode awareness.
"""

import os
import sys
from pathlib import Path
from typing import Optional, Dict, Any
from dataclasses import dataclass
import yaml
from endoreg_db.utils import DbConfig


@dataclass
class ConfigurationPaths:
    """Paths for configuration management."""
    conf_dir: Path
    conf_template_dir: Path
    working_dir: Path
    
    def __post_init__(self):
        """Ensure paths are Path objects."""
        self.conf_dir = Path(self.conf_dir).resolve()
        self.conf_template_dir = Path(self.conf_template_dir).resolve()
        self.working_dir = Path(self.working_dir).resolve()


class ConfigurationManager:
    """Manages configuration files for different deployment modes."""
    
    def __init__(self, paths: Optional[ConfigurationPaths] = None):
        self.paths = paths or self._load_paths_from_env()
        self.mode = os.environ.get("ENDO_API_MODE", "development")
        
    def _load_paths_from_env(self) -> ConfigurationPaths:
        """Load configuration paths from environment variables."""
        return ConfigurationPaths(
            conf_dir=Path(os.environ.get("CONF_DIR", "./conf")),
            conf_template_dir=Path(os.environ.get("CONF_TEMPLATE_DIR", "./conf_template")),
            working_dir=Path(os.environ.get("WORKING_DIR", ".")),
        )
    
    def setup_configuration(self) -> None:
        """Main entry point for configuration setup."""
        print(f"Setting up configuration for mode: {self.mode}")
        
        # Ensure directories exist
        self._ensure_directories()
        
        # Setup database configuration based on mode
        self._setup_database_config()
        
        # Setup other configuration files as needed
        self._setup_additional_configs()
        
        print("Configuration setup completed successfully!")
    
    def _ensure_directories(self) -> None:
        """Create necessary directories."""
        directories = [self.paths.conf_dir, self.paths.conf_template_dir]
        
        for directory in directories:
            if not directory.exists():
                print(f"Creating directory: {directory}")
                directory.mkdir(parents=True, exist_ok=True)
    
    def _setup_database_config(self) -> None:
        """Setup database configuration based on mode."""
        db_config_file = self.paths.conf_dir / "db.yaml"
        db_template_file = self.paths.conf_template_dir / "db.yaml"
        
        # Create template if it doesn't exist
        if not db_template_file.exists():
            self._create_database_template()
        
        # Generate actual config if it doesn't exist or if we're switching modes
        if not db_config_file.exists() or self._should_update_db_config():
            self._generate_database_config()
    
    def _create_database_template(self) -> None:
        """Create database configuration template based on mode."""
        db_template_file = self.paths.conf_template_dir / "db.yaml"
        
        if self.mode == "development":
            # Development uses SQLite, so minimal config needed
            template_config = {
                "engine": "django.db.backends.sqlite3",
                "name": "development.sqlite3",
                "user": "",
                "password": "",
                "host": "",
                "port": "",
                "password_file": ""
            }
        else:
            # Production/Central use PostgreSQL
            template_config = {
                "engine": "django.db.backends.postgresql",
                "name": "endoregDbLocal",
                "user": "endoregDbLocal",
                "host": "localhost",
                "port": 5432,
                "password_file": "conf/db_pwd"
            }
        
        print(f"Creating database template: {db_template_file}")
        with open(db_template_file, 'w') as f:
            yaml.dump(template_config, f, default_flow_style=False)
    
    def _should_update_db_config(self) -> bool:
        """Check if database config should be updated based on mode."""
        db_config_file = self.paths.conf_dir / "db.yaml"
        
        if not db_config_file.exists():
            return True
        
        # Check if current config matches expected mode
        try:
            with open(db_config_file, 'r') as f:
                current_config = yaml.safe_load(f)
            
            expected_engine = (
                "django.db.backends.sqlite3" if self.mode == "development" 
                else "django.db.backends.postgresql"
            )
            
            return current_config.get("engine") != expected_engine
            
        except Exception as e:
            print(f"Error reading current config: {e}")
            return True
    
    def _generate_database_config(self) -> None:
        """Generate database configuration from template."""
        db_template_file = self.paths.conf_template_dir / "db.yaml"
        db_config_file = self.paths.conf_dir / "db.yaml"
        
        if not db_template_file.exists():
            raise FileNotFoundError(f"Database template not found: {db_template_file}")
        
        try:
            # Load and validate template
            db_cfg = DbConfig.from_file(db_template_file)
            db_cfg.custom_validate()
            
            # Check if target file already has the same content
            if db_config_file.exists():
                try:
                    existing_cfg = DbConfig.from_file(db_config_file)
                    if existing_cfg.model_dump() == db_cfg.model_dump():
                        print(f"Database configuration {db_config_file} is already up to date")
                        return
                except Exception as e:
                    print(f"Warning: Could not compare existing config: {e}")
            
            # Write to target location only if content changed
            print(f"Generating database configuration: {db_config_file}")
            db_cfg.to_file(str(db_config_file), ask_override=True)
            print("Database configuration created successfully!")
            
        except Exception as e:
            raise RuntimeError(f"Failed to generate database configuration: {e}")
    
    def _setup_additional_configs(self) -> None:
        """Setup additional configuration files as needed."""
        # This method can be extended to handle other configuration files
        # For now, we focus on the database configuration
        pass
    
    def validate_configuration(self) -> bool:
        """Validate current configuration setup."""
        print("Validating configuration...")
        
        # Check if required files exist
        required_files = [
            self.paths.conf_dir / "db.yaml",
        ]
        
        missing_files = [f for f in required_files if not f.exists()]
        if missing_files:
            print(f"Missing configuration files: {missing_files}")
            return False
        
        # Validate database configuration
        try:
            db_config_file = self.paths.conf_dir / "db.yaml"
            db_cfg = DbConfig.from_file(db_config_file)
            db_cfg.custom_validate()
            print("Database configuration is valid")
        except Exception as e:
            print(f"Database configuration validation failed: {e}")
            return False
        
        print("Configuration validation completed successfully!")
        return True


def main():
    """Main entry point for configuration setup."""
    try:
        manager = ConfigurationManager()
        
        # Setup configuration
        manager.setup_configuration()
        
        # Validate configuration
        if not manager.validate_configuration():
            print("Configuration validation failed", file=sys.stderr)
            return 1
        
        return 0
        
    except Exception as e:
        print(f"Error during configuration setup: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
