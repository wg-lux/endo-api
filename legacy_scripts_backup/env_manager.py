#!/usr/bin/env python3
"""
Environment Management for Endo API
===================================

This module provides a clean, modular approach to environment setup,
replacing the legacy env_setup.py with better structure and mode awareness.
It now reads configuration from the centralized app_config.nix file.
"""

import os
import sys
import json
import subprocess
from pathlib import Path
from typing import Dict, Optional, Set, Any
from dataclasses import dataclass
from django.core.management.utils import get_random_secret_key
import yaml


@dataclass
class EnvironmentConfig:
    """Configuration settings for environment setup."""
    mode: str = "development"  # development, production, central
    working_dir: Path = Path.cwd()
    conf_dir: Path = Path("./conf")
    conf_template_dir: Path = Path("./conf_template")
    data_dir: Path = Path("./data")
    
    def __post_init__(self):
        """Ensure paths are Path objects."""
        for field_name in ['working_dir', 'conf_dir', 'conf_template_dir', 'data_dir']:
            value = getattr(self, field_name)
            if not isinstance(value, Path):
                setattr(self, field_name, Path(value))


class EnvironmentManager:
    """Manages environment setup for different deployment modes."""
    
    def __init__(self, config: Optional[EnvironmentConfig] = None):
        self.config = config or self._load_config_from_env()
        self.env_file = self.config.working_dir / ".env"
        self.app_config = self._load_app_config()
        
    def _load_app_config(self) -> Dict[str, Any]:
        """Load configuration from app_config.nix using nix evaluation."""
        try:
            # Read individual values using nix-instantiate
            config = {}
            
            # Server configuration
            result = subprocess.run(['nix-instantiate', '--eval', '--strict', '--json', 
                                   'app_config.nix', '-A', 'server.host'], 
                                   capture_output=True, text=True)
            if result.returncode == 0:
                config['server_host'] = json.loads(result.stdout.strip())
            
            result = subprocess.run(['nix-instantiate', '--eval', '--strict', '--json', 
                                   'app_config.nix', '-A', 'server.port'], 
                                   capture_output=True, text=True)
            if result.returncode == 0:
                config['server_port'] = json.loads(result.stdout.strip())
            
            result = subprocess.run(['nix-instantiate', '--eval', '--strict', '--json', 
                                   'app_config.nix', '-A', 'app.djangoModule'], 
                                   capture_output=True, text=True)
            if result.returncode == 0:
                config['django_module'] = json.loads(result.stdout.strip())
            
            result = subprocess.run(['nix-instantiate', '--eval', '--strict', '--json', 
                                   'app_config.nix', '-A', 'app.name'], 
                                   capture_output=True, text=True)
            if result.returncode == 0:
                config['app_name'] = json.loads(result.stdout.strip())
                
            return config
            
        except Exception as e:
            print(f"Warning: Could not load app_config.nix: {e}")
            return {}
    
    def _default_app_config(self) -> Dict:
        """Fallback configuration if app_config.nix cannot be loaded"""
        return {
            "app": {"name": "endo-api", "djangoModule": "endo_api"},
            "server": {"host": "localhost", "port": "8118", "protocol": "http"},
            "paths": {"data": "./data", "conf": "./conf"}
        }
        
    def _load_config_from_env(self) -> EnvironmentConfig:
        """Load configuration from environment variables."""
        mode = os.environ.get("ENDO_API_MODE", "development")
        
        return EnvironmentConfig(
            mode=mode,
            working_dir=Path(os.environ.get("WORKING_DIR", ".")),
            conf_dir=Path(os.environ.get("CONF_DIR", "./conf")),
            conf_template_dir=Path(os.environ.get("CONF_TEMPLATE_DIR", "./conf_template")),
            data_dir=Path(os.environ.get("DATA_DIR", "./data")),
        )
    
    def setup_environment(self, force_update: bool = False) -> bool:
        """Setup the environment file with current configuration."""
        try:
            env_vars = self._generate_env_vars()
            
            if env_vars:
                # Check if file exists and compare
                if self.env_file.exists() and not force_update:
                    existing = self._load_existing_env()
                    if self._env_needs_update(existing, env_vars):
                        merged = self._merge_env_vars(existing, env_vars)
                        self._write_env_file(merged)
                        print(f"Environment file {self.env_file} updated with new configuration")
                    else:
                        print(f"Environment file {self.env_file} is already up to date")
                else:
                    # Force update or no existing file
                    existing = self._load_existing_env() if self.env_file.exists() else {}
                    merged = self._merge_env_vars(existing, env_vars) 
                    self._write_env_file(merged)
                    action = "updated" if self.env_file.exists() else "created"
                    print(f"Environment file {self.env_file} {action}")
                
                return True
            else:
                print("Warning: No environment variables generated")
                return False
                
        except Exception as e:
            print(f"Error during environment setup: {e}")
            return False
    
    def _ensure_directories(self) -> None:
        """Create necessary directories if they don't exist."""
        directories = [
            self.config.conf_dir,
            self.config.data_dir,
            self.config.data_dir / "import",
            self.config.data_dir / "export",
            self.config.data_dir / "videos",
            self.config.data_dir / "frames",
            self.config.data_dir / "pdfs",
            self.config.data_dir / "model_weights",
        ]
        
        for directory in directories:
            if not directory.exists():
                print(f"Creating directory: {directory}")
                directory.mkdir(parents=True, exist_ok=True)
    
    def _setup_configuration_files(self) -> None:
        """Setup configuration files (database password, etc.)."""
        # Database password file
        db_pwd_file = self.config.conf_dir / "db_pwd"
        if not db_pwd_file.exists():
            print(f"Creating database password file: {db_pwd_file}")
            with open(db_pwd_file, 'w') as f:
                if self.config.mode == "development":
                    f.write("localdev123")
                else:
                    f.write("changeme_in_production")
            print("IMPORTANT: Change the database password for production deployments!")
    
    def _setup_env_file(self) -> None:
        """Generate or update the .env file based on current mode."""
        # Load existing .env if it exists
        existing_vars = self._load_existing_env()
        
        # Generate the environment variables for current mode
        env_vars = self._generate_env_vars()
        
        # Merge existing with new, preferring existing for secrets
        merged_vars = self._merge_env_vars(existing_vars, env_vars)
        
        # Write the .env file
        self._write_env_file(merged_vars)
    
    def _load_existing_env(self) -> Dict[str, str]:
        """Load existing environment variables from .env file."""
        if not self.env_file.exists():
            return {}
        
        env_vars = {}
        with open(self.env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
        
        return env_vars
    
    def _generate_env_vars(self) -> Dict[str, str]:
        """Generate environment variables based on current mode and centralized config."""
        base_vars = {
            # Basic Django settings - now from centralized config
            "DJANGO_DEBUG": "True" if self.config.mode == "development" else "False",
            "DJANGO_HOST": os.environ.get("DJANGO_HOST", self.app_config.get("server_host", "localhost")),
            "DJANGO_PORT": os.environ.get("DJANGO_PORT", self.app_config.get("server_port", "8118")),
            "DJANGO_MODULE": os.environ.get("DJANGO_MODULE", self.app_config.get("django_module", "endo_api")),
            
            # Paths - using default values since paths aren't in simplified config
            "DATA_DIR": str((self.config.working_dir / "data").resolve()),
            "CONF_DIR": str((self.config.working_dir / "conf").resolve()),
            "WORKING_DIR": str(self.config.working_dir.resolve()),
            "STORAGE_DIR": str((self.config.working_dir / "data").resolve()),
            "IMPORT_DIR": str((self.config.working_dir / "data/import").resolve()),
            
            # Application settings - could also be made configurable
            "TEST_RUN": "False",
            "TEST_RUN_FRAME_NUMBER": "1000",
            "RUST_BACKTRACE": "1",
            "DJANGO_FFMPEG_EXTRACT_FRAME_BATCHSIZE": "500",
            "LABEL_VIDEO_SEGMENT_MIN_DURATION_S_FOR_ANNOTATION": "3",
        }
        
        # Mode-specific settings - using centralized config
        django_module = self.app_config.get("django_module", "endo_api")
        if self.config.mode == "development":
            base_vars.update({
                "DJANGO_SETTINGS_MODULE": f"{django_module}.settings_dev",
                "DATABASE_ENGINE": "sqlite3",
            })
        elif self.config.mode == "production":
            base_vars.update({
                "DJANGO_SETTINGS_MODULE": f"{django_module}.settings_prod",
                "DATABASE_ENGINE": "postgresql",
                "DB_CONFIG_FILE": str((self.config.working_dir / "conf" / "db.yaml").resolve()),
            })
        elif self.config.mode == "central":
            base_vars.update({
                "DJANGO_SETTINGS_MODULE": f"{django_module}.settings_central",
                "DATABASE_ENGINE": "postgresql", 
                "DB_CONFIG_FILE": str((self.config.working_dir / "conf" / "db.yaml").resolve()),
                "CENTRAL_NODE": "true",
            })
        
        return base_vars
    
    def _merge_env_vars(self, existing: Dict[str, str], new: Dict[str, str]) -> Dict[str, str]:
        """Merge existing and new environment variables, preserving secrets."""
        merged = new.copy()
        
        # Preserve existing secrets and user-customized values
        preserve_keys = {
            "DJANGO_SECRET_KEY", "DJANGO_SALT", "DATABASE_PASSWORD",
            # Add other sensitive keys that should be preserved
        }
        
        for key, value in existing.items():
            if key in preserve_keys or key not in merged:
                merged[key] = value
        
        # Generate secrets if they don't exist
        if "DJANGO_SECRET_KEY" not in merged:
            merged["DJANGO_SECRET_KEY"] = get_random_secret_key()
        
        if "DJANGO_SALT" not in merged:
            merged["DJANGO_SALT"] = get_random_secret_key()
        
        return merged
    
    def _write_env_file(self, env_vars: Dict[str, str]) -> None:
        """Write environment variables to .env file."""
        
        lines = [
            "# Auto-generated environment file for Endo API",
            f"# Mode: {self.config.mode}",
            f"# Generated on: {os.environ.get('USER', 'unknown')}@{os.uname().nodename}",
            "",
        ]
        
        # Group variables by category for better readability
        categories = {
            "Django Core": ["DJANGO_SETTINGS_MODULE", "DJANGO_DEBUG", "DJANGO_SECRET_KEY", "DJANGO_SALT"],
            "Server Configuration": ["DJANGO_HOST", "DJANGO_PORT", "DJANGO_MODULE"],
            "Database": ["DATABASE_ENGINE", "DB_CONFIG_FILE", "DATABASE_PASSWORD"],
            "Paths": ["DATA_DIR", "CONF_DIR", "WORKING_DIR", "STORAGE_DIR", "IMPORT_DIR"],
            "Application Settings": ["TEST_RUN", "RUST_BACKTRACE", "DJANGO_FFMPEG_EXTRACT_FRAME_BATCHSIZE"],
        }
        
        # Write categorized variables
        written_keys = set()
        for category, keys in categories.items():
            category_vars = {k: v for k, v in env_vars.items() if k in keys and k in env_vars}
            if category_vars:
                lines.append(f"# {category}")
                for key in keys:
                    if key in env_vars:
                        value = env_vars[key]
                        # Remove existing quotes if present before adding new ones
                        if isinstance(value, str) and value.startswith('"') and value.endswith('"'):
                            value = value[1:-1]  # Remove surrounding quotes
                        
                        # Quote values that contain special characters
                        if key in ["DJANGO_SECRET_KEY", "DJANGO_SALT"] or any(char in str(value) for char in ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')', ' ']):
                            lines.append(f'{key}="{value}"')
                        else:
                            lines.append(f"{key}={value}")
                        written_keys.add(key)
                lines.append("")
        
        # Write remaining variables
        remaining_vars = {k: v for k, v in env_vars.items() if k not in written_keys}
        if remaining_vars:
            lines.append("# Other Settings")
            for key, value in sorted(remaining_vars.items()):
                # Remove existing quotes if present before adding new ones
                if isinstance(value, str) and value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]  # Remove surrounding quotes
                    
                # Quote values that contain special characters
                if key in ["DJANGO_SECRET_KEY", "DJANGO_SALT"] or any(char in str(value) for char in ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')', ' ']):
                    lines.append(f'{key}="{value}"')
                else:
                    lines.append(f"{key}={value}")
        
        # Prepare new content
        new_content = '\n'.join(lines)
        
        # Check if file exists and compare content
        if self.env_file.exists():
            try:
                with open(self.env_file, 'r') as f:
                    existing_content = f.read()
                
                # Only write if content has changed
                if existing_content == new_content:
                    print(f"Environment file {self.env_file} is already up to date")
                    return
            except (IOError, OSError) as e:
                print(f"Warning: Could not read existing file {self.env_file}: {e}")
        
        # Write to file only if content changed or file doesn't exist
        print(f"Writing environment file: {self.env_file}")
        with open(self.env_file, 'w') as f:
            f.write(new_content)
        
        print(f"Environment file created with {len(env_vars)} variables")


def main():
    """Main entry point for environment setup."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Environment setup for Endo API")
    parser.add_argument("--force", action="store_true", 
                       help="Force regeneration of environment file")
    parser.add_argument("--mode", default="development",
                       choices=["development", "production", "central"],
                       help="Environment mode")
    
    args = parser.parse_args()
    
    try:
        # Create config with specified mode  
        from pathlib import Path
        config = EnvironmentConfig(
            mode=args.mode,
            working_dir=Path.cwd()
        )
        manager = EnvironmentManager(config=config)
        manager.setup_environment(force_update=args.force)
        return 0
    except Exception as e:
        print(f"Error during environment setup: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
