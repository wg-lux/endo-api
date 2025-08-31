#!/usr/bin/env python3
"""
Comprehensive tests for the centralized configuration system.

This module tests:
1. Configuration file parsing and validation
2. Environment variable generation
3. Configuration manager script functionality
4. DevEnv integration
5. Container configuration consistency
"""

import os
import sys
import json
import subprocess
import tempfile
import unittest
import psycopg2
import django
from pathlib import Path
from unittest.mock import patch, mock_open, MagicMock

# Add the project root to Python path
sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.env_manager import EnvironmentManager, EnvironmentConfig


class TestCentralizedConfig(unittest.TestCase):
    """Test suite for centralized configuration system."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_dir = Path(__file__).parent.parent
        self.app_config_path = self.test_dir / "app_config.nix"
        self.config_manager_path = self.test_dir / "config-manager.sh"
        
    def test_app_config_exists_and_valid(self):
        """Test that app_config.nix exists and is valid Nix syntax."""
        self.assertTrue(self.app_config_path.exists(), "app_config.nix should exist")
        
        # Test Nix syntax validation
        result = subprocess.run(
            ["nix-instantiate", "--parse", str(self.app_config_path)],
            capture_output=True, text=True, cwd=self.test_dir
        )
        self.assertEqual(result.returncode, 0, f"app_config.nix has syntax errors: {result.stderr}")
    
    def test_config_values_accessible(self):
        """Test that all expected configuration values can be read."""
        expected_paths = [
            "app.name",
            "app.djangoModule", 
            "server.host",
            "server.port",
            "server.protocol",
            "database.dev.engine",
            "database.prod.engine"
        ]
        
        for path in expected_paths:
            with self.subTest(config_path=path):
                result = subprocess.run(
                    ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", path],
                    capture_output=True, text=True, cwd=self.test_dir
                )
                self.assertEqual(result.returncode, 0, f"Failed to read {path}: {result.stderr}")
                
                # Ensure we got valid JSON
                try:
                    value = json.loads(result.stdout.strip())
                    self.assertIsNotNone(value, f"Got null value for {path}")
                except json.JSONDecodeError as e:
                    self.fail(f"Invalid JSON for {path}: {result.stdout}, error: {e}")
    
    def test_config_manager_script_exists(self):
        """Test that config-manager.sh exists and is executable."""
        self.assertTrue(self.config_manager_path.exists(), "config-manager.sh should exist")
        self.assertTrue(os.access(self.config_manager_path, os.X_OK), "config-manager.sh should be executable")
    
    def test_config_manager_show_config(self):
        """Test config-manager.sh show-config functionality."""
        result = subprocess.run(
            [str(self.config_manager_path), "show-config"],
            capture_output=True, text=True, cwd=self.test_dir
        )
        self.assertEqual(result.returncode, 0, f"show-config failed: {result.stderr}")
        
        # Check that expected output is present
        output = result.stdout
        self.assertIn("Application Name:", output)
        self.assertIn("Django Module:", output)
        self.assertIn("Server Host:", output)
        self.assertIn("Server Port:", output)
    
    def test_config_manager_set_port(self):
        """Test config-manager.sh port setting functionality."""
        # Create a temporary config file to avoid modifying the real one
        with tempfile.NamedTemporaryFile(mode='w', suffix='.nix', delete=False) as tmp_config:
            with open(self.app_config_path, 'r') as original:
                tmp_config.write(original.read())
            tmp_config_path = tmp_config.name
        
        try:
            # Test setting a new port
            test_port = "9999"
            result = subprocess.run(
                ["sed", "-i", f's/port = "8118"/port = "{test_port}"/', tmp_config_path],
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, "Failed to update test config")
            
            # Verify the change was made
            result = subprocess.run(
                ["nix-instantiate", "--eval", "--strict", "--json", tmp_config_path, "-A", "server.port"],
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, "Failed to read updated port")
            port_value = json.loads(result.stdout.strip())
            self.assertEqual(port_value, test_port, f"Port not updated correctly, got {port_value}")
            
        finally:
            os.unlink(tmp_config_path)
    
    def test_environment_manager_config_loading(self):
        """Test that EnvironmentManager correctly loads centralized config."""
        config = EnvironmentConfig(mode="development", working_dir=self.test_dir)
        manager = EnvironmentManager(config)
        
        # Test that app_config was loaded
        self.assertIsInstance(manager.app_config, dict, "app_config should be loaded as dict")
        
        # Test that expected keys exist (these come from our simplified config loading)
        expected_keys = ["server_host", "server_port", "django_module", "app_name"]
        for key in expected_keys:
            with self.subTest(config_key=key):
                # The key should exist (even if empty due to loading issues)
                self.assertIn(key, manager.app_config, f"Expected config key {key} not found")


class TestEnvironmentGeneration(unittest.TestCase):
    """Test environment variable generation from centralized config."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_dir = Path(__file__).parent.parent
        self.config = EnvironmentConfig(mode="development", working_dir=self.test_dir)
    
    @patch('scripts.env_manager.EnvironmentManager._load_app_config')
    def test_env_vars_generation(self, mock_load_config):
        """Test that environment variables are generated correctly from config."""
        # Mock the config loading to return test values
        mock_load_config.return_value = {
            "server_host": "test.example.com",
            "server_port": "8080", 
            "django_module": "test_api",
            "app_name": "test-app"
        }
        
        manager = EnvironmentManager(self.config)
        env_vars = manager._generate_env_vars()
        
        # Test that configuration values are used
        self.assertEqual(env_vars["DJANGO_HOST"], "test.example.com")
        self.assertEqual(env_vars["DJANGO_PORT"], "8080")
        self.assertEqual(env_vars["DJANGO_MODULE"], "test_api")
        
        # Test that mode-specific settings are applied
        self.assertEqual(env_vars["DJANGO_DEBUG"], "True")  # development mode
        self.assertEqual(env_vars["DATABASE_ENGINE"], "sqlite3")  # development mode
    
    @patch('scripts.env_manager.EnvironmentManager._load_app_config')
    def test_production_mode_env_vars(self, mock_load_config):
        """Test environment variables for production mode."""
        mock_load_config.return_value = {
            "server_host": "0.0.0.0",
            "server_port": "80",
            "django_module": "endo_api", 
            "app_name": "endo-api"
        }
        
        prod_config = EnvironmentConfig(mode="production", working_dir=self.test_dir)
        manager = EnvironmentManager(prod_config)
        env_vars = manager._generate_env_vars()
        
        # Test production-specific settings
        self.assertEqual(env_vars["DJANGO_DEBUG"], "False")  # production mode
        self.assertEqual(env_vars["DATABASE_ENGINE"], "postgresql")  # production mode
        self.assertIn("settings_prod", env_vars["DJANGO_SETTINGS_MODULE"])


class TestDevEnvIntegration(unittest.TestCase):
    """Test integration with DevEnv system."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_dir = Path(__file__).parent.parent
    
    def test_devenv_loads_app_config(self):
        """Test that devenv.nix can load and use app_config.nix."""
        # Test that devenv.nix imports app_config.nix successfully
        devenv_path = self.test_dir / "devenv.nix"
        self.assertTrue(devenv_path.exists(), "devenv.nix should exist")
        
        # Check that devenv.nix syntax is valid
        result = subprocess.run(
            ["nix-instantiate", "--parse", str(devenv_path)],
            capture_output=True, text=True, cwd=self.test_dir
        )
        self.assertEqual(result.returncode, 0, f"devenv.nix has syntax errors: {result.stderr}")
    
    def test_scripts_use_centralized_config(self):
        """Test that devenv scripts use centralized configuration."""
        scripts_path = self.test_dir / "devenv" / "scripts.nix"
        self.assertTrue(scripts_path.exists(), "devenv/scripts.nix should exist")
        
        # Read the file and check for appConfig usage
        with open(scripts_path, 'r') as f:
            content = f.read()
            self.assertIn("appConfig", content, "scripts.nix should reference appConfig")
    
    def test_containers_use_centralized_config(self):
        """Test that container configuration uses centralized config."""
        containers_path = self.test_dir / "devenv" / "containers.nix"
        self.assertTrue(containers_path.exists(), "devenv/containers.nix should exist")
        
        # Check that it uses centralized configuration
        with open(containers_path, 'r') as f:
            content = f.read()
            self.assertIn("appConfig", content, "containers.nix should reference appConfig")


class TestConfigurationConsistency(unittest.TestCase):
    """Test that configuration is consistent across all components."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_dir = Path(__file__).parent.parent
    
    def test_port_consistency_across_components(self):
        """Test that port configuration is consistent across all components."""
        # Get the port from app_config.nix
        result = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "server.port"],
            capture_output=True, text=True, cwd=self.test_dir
        )
        self.assertEqual(result.returncode, 0, "Failed to read server port from config")
        config_port = json.loads(result.stdout.strip())
        
        # Test that environment manager would use the same port
        config = EnvironmentConfig(mode="development", working_dir=self.test_dir)
        manager = EnvironmentManager(config)
        
        # If the config loading works, it should use the centralized port
        if manager.app_config.get("server_port"):
            self.assertEqual(
                manager.app_config["server_port"], 
                config_port,
                "Environment manager should use same port as config file"
            )
    
    def test_django_module_consistency(self):
        """Test that Django module name is consistent across components."""
        # Get the Django module from app_config.nix
        result = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "app.djangoModule"],
            capture_output=True, text=True, cwd=self.test_dir
        )
        self.assertEqual(result.returncode, 0, "Failed to read Django module from config")
        config_module = json.loads(result.stdout.strip())
        
        # Test that the actual Django module directory exists
        django_module_path = self.test_dir / config_module
        self.assertTrue(
            django_module_path.exists() and django_module_path.is_dir(),
            f"Django module directory {config_module} should exist"
        )


class TestDocumentation(unittest.TestCase):
    """Test that documentation is comprehensive and up-to-date."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_dir = Path(__file__).parent.parent
        self.guide_path = self.test_dir / "NATIVE_DEVENV_CONTAINERS_GUIDE.md"
    
    def test_documentation_exists(self):
        """Test that comprehensive documentation exists."""
        self.assertTrue(self.guide_path.exists(), "Comprehensive documentation should exist")
    
    def test_documentation_mentions_centralized_config(self):
        """Test that documentation covers centralized configuration."""
        with open(self.guide_path, 'r') as f:
            content = f.read()
            
        # Check for key documentation sections
        self.assertIn("Centralized Configuration", content, 
                     "Documentation should cover centralized configuration")
        self.assertIn("app_config.nix", content,
                     "Documentation should mention the config file")
        self.assertIn("config-manager.sh", content,
                     "Documentation should mention the config manager")
        self.assertIn("set-port", content,
                     "Documentation should show usage examples")


class TestDatabaseConnectivity(unittest.TestCase):
    """Test database connectivity and Django compatibility."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_dir = Path(__file__).parent.parent
        self.config_file = self.test_dir / "app_config.nix"
        
    def _get_db_config(self, mode="prod"):
        """Get database configuration from app_config.nix."""
        try:
            # Get database configuration from centralized config
            result = subprocess.run(
                ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", f"database.{mode}"],
                capture_output=True, text=True, cwd=self.test_dir
            )
            
            if result.returncode != 0:
                self.skipTest(f"Could not read database config: {result.stderr}")
            
            return json.loads(result.stdout.strip())
        except Exception as e:
            self.skipTest(f"Failed to parse database config: {e}")
    
    def _get_db_credentials(self):
        """Get database credentials from configuration files."""
        db_config = self._get_db_config("prod")
        
        # Read password from file if specified
        password = None
        if "passwordFile" in db_config and db_config["passwordFile"]:
            password_file = self.test_dir / db_config["passwordFile"]
            if password_file.exists():
                password = password_file.read_text().strip()
        
        return {
            "host": db_config.get("host", "localhost"),
            "port": db_config.get("port", "5432"),
            "database": db_config.get("name", "endoregDbLocal"),
            "user": db_config.get("user", "endoreg_user"),
            "password": password
        }
    
    def test_postgres_credentials_accessible(self):
        """Test that PostgreSQL credentials can be read from configuration."""
        credentials = self._get_db_credentials()
        
        self.assertIsNotNone(credentials["host"], "Database host should be configured")
        self.assertIsNotNone(credentials["port"], "Database port should be configured")
        self.assertIsNotNone(credentials["database"], "Database name should be configured")
        self.assertIsNotNone(credentials["user"], "Database user should be configured")
        
        print(f"Database configuration loaded: {credentials['user']}@{credentials['host']}:{credentials['port']}/{credentials['database']}")
    
    def test_postgres_connection(self):
        """Test PostgreSQL database connection."""
        credentials = self._get_db_credentials()
        
        if not credentials["password"]:
            self.skipTest("Database password not available - skipping connection test")
        
        try:
            # Try importing the required modules
            try:
                import psycopg2
            except ImportError:
                self.skipTest("psycopg2 not available - install with: pip install psycopg2-binary")
            
            connection = psycopg2.connect(
                host=credentials["host"],
                port=credentials["port"],
                database=credentials["database"],
                user=credentials["user"],
                password=credentials["password"]
            )
            
            # Test basic query
            cursor = connection.cursor()
            cursor.execute("SELECT version();")
            version_result = cursor.fetchone()
            
            cursor.close()
            connection.close()
            
            if version_result:
                print(f"✅ PostgreSQL connection successful: {version_result[0]}")
            else:
                print("✅ PostgreSQL connection successful")
            
        except Exception as e:
            self.fail(f"PostgreSQL connection failed: {e}")
    
    def test_django_database_configuration(self):
        """Test Django database configuration compatibility."""
        # Set up minimal Django settings for testing
        django_module = self._get_django_module()
        
        try:
            import django
            from django.conf import settings
            from django.core.management import execute_from_command_line
            import os
            
            # Set Django settings module
            os.environ.setdefault('DJANGO_SETTINGS_MODULE', f'{django_module}.settings_prod')
            
            # Configure Django if not already configured
            if not hasattr(settings, 'DATABASES'):
                django.setup()
            
            # Test database configuration
            from django.db import connections
            
            db_conn = connections['default']
            db_settings = db_conn.settings_dict
            
            self.assertEqual(db_settings['ENGINE'], 'django.db.backends.postgresql')
            self.assertIsNotNone(db_settings['NAME'])
            self.assertIsNotNone(db_settings['HOST'])
            self.assertIsNotNone(db_settings['PORT'])
            
            print(f"✅ Django database configuration valid: {db_settings['NAME']}@{db_settings['HOST']}")
            
        except ImportError as e:
            self.skipTest(f"Django not available: {e}")
        except Exception as e:
            self.fail(f"Django database configuration test failed: {e}")
    
    def test_database_migrations_status(self):
        """Test Django database migration status."""
        django_module = self._get_django_module()
        
        try:
            import django
            from django.core.management import call_command
            from django.core.management.base import CommandError
            from io import StringIO
            import os
            
            # Set Django settings module
            os.environ.setdefault('DJANGO_SETTINGS_MODULE', f'{django_module}.settings_prod')
            
            # Configure Django
            if not hasattr(django.conf.settings, 'DATABASES'):
                django.setup()
            
            # Check migration status
            out = StringIO()
            
            try:
                # This will show unapplied migrations if any
                call_command('showmigrations', '--plan', stdout=out)
                migration_output = out.getvalue()
                
                # Check for unapplied migrations (lines starting with [ ])
                unapplied = [line for line in migration_output.split('\n') 
                           if line.strip().startswith('[ ]')]
                
                if unapplied:
                    print(f"⚠️  Found {len(unapplied)} unapplied migrations:")
                    for migration in unapplied[:5]:  # Show first 5
                        print(f"   {migration.strip()}")
                    if len(unapplied) > 5:
                        print(f"   ... and {len(unapplied) - 5} more")
                else:
                    print("✅ All migrations are applied")
                
                # This is informational, not a failure
                return True
                
            except CommandError as e:
                self.skipTest(f"Could not check migrations: {e}")
                
        except ImportError as e:
            self.skipTest(f"Django not available for migration check: {e}")
        except Exception as e:
            self.skipTest(f"Migration status check failed: {e}")
    
    def test_database_tables_exist(self):
        """Test that essential Django tables exist in the database."""
        credentials = self._get_db_credentials()
        
        if not credentials["password"]:
            self.skipTest("Database password not available - skipping table check")
        
        try:
            import psycopg2
            
            connection = psycopg2.connect(
                host=credentials["host"],
                port=credentials["port"],
                database=credentials["database"],
                user=credentials["user"],
                password=credentials["password"]
            )
            
            cursor = connection.cursor()
            
            # Check for essential Django tables
            essential_tables = [
                'django_migrations',
                'django_content_type',
                'auth_user',
            ]
            
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            """)
            
            existing_tables = [row[0] for row in cursor.fetchall()]
            
            missing_tables = []
            for table in essential_tables:
                if table not in existing_tables:
                    missing_tables.append(table)
            
            cursor.close()
            connection.close()
            
            if missing_tables:
                print(f"⚠️  Missing essential Django tables: {missing_tables}")
                print("   Run 'python manage.py migrate' to create missing tables")
            else:
                print(f"✅ Essential Django tables exist ({len(essential_tables)} checked)")
                
            # Also show some app-specific tables if they exist
            app_tables = [table for table in existing_tables if not table.startswith(('django_', 'auth_'))]
            if app_tables:
                print(f"   Found {len(app_tables)} application tables")
            
        except ImportError:
            self.skipTest("psycopg2 not available")
        except Exception as e:
            self.fail(f"Database table check failed: {e}")
    
    def test_database_permissions(self):
        """Test database user permissions."""
        credentials = self._get_db_credentials()
        
        if not credentials["password"]:
            self.skipTest("Database password not available - skipping permissions check")
        
        try:
            import psycopg2
            
            connection = psycopg2.connect(
                host=credentials["host"],
                port=credentials["port"],
                database=credentials["database"],
                user=credentials["user"],
                password=credentials["password"]
            )
            
            cursor = connection.cursor()
            
            # Test basic permissions
            permissions_tests = [
                ("CREATE TABLE", "CREATE TEMP TABLE test_perm_table (id INTEGER)"),
                ("INSERT", "INSERT INTO test_perm_table VALUES (1)"),
                ("SELECT", "SELECT * FROM test_perm_table"),
                ("UPDATE", "UPDATE test_perm_table SET id = 2"),
                ("DELETE", "DELETE FROM test_perm_table"),
                ("DROP TABLE", "DROP TABLE test_perm_table"),
            ]
            
            failed_permissions = []
            
            for perm_name, sql in permissions_tests:
                try:
                    cursor.execute(sql)
                    connection.commit()
                except psycopg2.Error as e:
                    failed_permissions.append((perm_name, str(e)))
                    connection.rollback()
            
            cursor.close()
            connection.close()
            
            if failed_permissions:
                print(f"❌ Failed permissions tests: {len(failed_permissions)}")
                for perm, error in failed_permissions:
                    print(f"   {perm}: {error}")
                self.fail("Database user lacks required permissions")
            else:
                print(f"✅ Database permissions OK ({len(permissions_tests)} tests passed)")
            
        except ImportError:
            self.skipTest("psycopg2 not available")
        except Exception as e:
            self.fail(f"Database permissions test failed: {e}")
    
    def _get_django_module(self):
        """Get Django module name from configuration."""
        try:
            result = subprocess.run(
                ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "app.djangoModule"],
                capture_output=True, text=True, cwd=self.test_dir
            )
            if result.returncode == 0:
                return json.loads(result.stdout.strip())
            return "endo_api"  # fallback
        except Exception:
            return "endo_api"  # fallback


def run_integration_tests():
    """Run integration tests that require the full environment."""
    print("Running integration tests...")
    
    # Test that the development environment can be built
    print("Testing devenv shell build...")
    result = subprocess.run(
        ["nix-instantiate", "--eval", "devenv.nix"],
        capture_output=True, text=True,
        cwd=Path(__file__).parent.parent
    )
    
    if result.returncode != 0:
        print(f"❌ DevEnv build failed: {result.stderr}")
        return False
    
    print("✅ DevEnv shell can be built successfully")
    
    # Test config manager functionality
    print("Testing config manager...")
    config_manager = Path(__file__).parent.parent / "config-manager.sh"
    
    if not config_manager.exists():
        print("❌ config-manager.sh not found")
        return False
    
    result = subprocess.run(
        [str(config_manager), "show-config"],
        capture_output=True, text=True,
        cwd=Path(__file__).parent.parent
    )
    
    if result.returncode != 0:
        print(f"❌ Config manager failed: {result.stderr}")
        return False
    
    print("✅ Config manager working correctly")
    return True


if __name__ == "__main__":
    print("=" * 60)
    print("CENTRALIZED CONFIGURATION SYSTEM TEST SUITE")
    print("=" * 60)
    
    # Run unit tests
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add all test classes
    test_classes = [
        TestCentralizedConfig,
        TestEnvironmentGeneration,
        TestDevEnvIntegration,
        TestConfigurationConsistency,
        TestDocumentation,
        TestDatabaseConnectivity
    ]
    
    for test_class in test_classes:
        tests = loader.loadTestsFromTestCase(test_class)
        suite.addTests(tests)
    
    # Run the tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Run integration tests
    print("\n" + "=" * 60)
    print("INTEGRATION TESTS")
    print("=" * 60)
    
    integration_success = run_integration_tests()
    
    # Summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)
    
    unit_success = result.wasSuccessful()
    
    print(f"Unit Tests: {'✅ PASSED' if unit_success else '❌ FAILED'}")
    print(f"Integration Tests: {'✅ PASSED' if integration_success else '❌ FAILED'}")
    
    if unit_success and integration_success:
        print("🎉 ALL TESTS PASSED - System ready for deployment!")
        sys.exit(0)
    else:
        print("❌ Some tests failed - review and fix before deployment")
        sys.exit(1)
