"""
Test database configuration logic in settings_base.env module.

Tests environment variable prioritization, .env file fallback, and various
database configuration scenarios including DATABASE_URL parsing and individual
DB_* variables.
"""

import os
import tempfile
import json
from unittest import TestCase
from unittest.mock import patch, mock_open
from urllib.parse import quote

from endo_api.settings_base.env import db_config


class TestDatabaseConfiguration(TestCase):
    """Test database configuration with various environment setups."""

    def setUp(self):
        """Reset environment before each test."""
        # Store original environment to restore later
        self.original_env = dict(os.environ)
        
        # Clear all database-related environment variables
        db_vars = [
            'DATABASE_URL', 'DB_ENGINE', 'DB_NAME', 'DB_USER', 'DB_PASSWORD',
            'DB_HOST', 'DB_PORT', 'DB_SSLMODE', 'DB_SSLROOTCERT', 'DB_SSLCERT',
            'DB_SSLKEY', 'DB_SSLROOTCERT_B64', 'DB_SSLCERT_B64', 'DB_SSLKEY_B64',
            'DJANGO_DB_OPTIONS'
        ]
        for var in db_vars:
            os.environ.pop(var, None)

    def tearDown(self):
        """Restore original environment after each test."""
        os.environ.clear()
        os.environ.update(self.original_env)

    def test_database_url_takes_priority(self):
        """Test that DATABASE_URL takes priority over individual DB_* variables."""
        # Set both DATABASE_URL and individual variables
        os.environ['DATABASE_URL'] = 'postgresql://url_user:url_pass@url_host:5433/url_db'
        os.environ['DB_NAME'] = 'individual_db'
        os.environ['DB_USER'] = 'individual_user'
        os.environ['DB_PASSWORD'] = 'individual_pass'
        os.environ['DB_HOST'] = 'individual_host'
        os.environ['DB_PORT'] = '5434'

        config = db_config()
        
        # Should use DATABASE_URL values, not individual variables
        self.assertEqual(config['default']['ENGINE'], 'django.db.backends.postgresql')
        self.assertEqual(config['default']['NAME'], 'url_db')
        self.assertEqual(config['default']['USER'], 'url_user')
        self.assertEqual(config['default']['PASSWORD'], 'url_pass')
        self.assertEqual(config['default']['HOST'], 'url_host')
        self.assertEqual(config['default']['PORT'], '5433')

    def test_database_url_with_encoded_credentials(self):
        """Test DATABASE_URL parsing with URL-encoded credentials."""
        # Use URL-encoded username and password
        encoded_user = 'user%40domain.com'  # user@domain.com encoded
        encoded_pass = 'pass%2Fword%23special'  # pass/word#special encoded
        os.environ['DATABASE_URL'] = f'postgresql://{encoded_user}:{encoded_pass}@host:5432/testdb'

        config = db_config()
        
        self.assertEqual(config['default']['USER'], 'user@domain.com')
        self.assertEqual(config['default']['PASSWORD'], 'pass/word#special')

    def test_database_url_partial_with_fallback(self):
        """Test DATABASE_URL with missing components falls back to environment."""
        # DATABASE_URL missing password and port
        os.environ['DATABASE_URL'] = 'postgresql://testuser@testhost/testdb'
        os.environ['DB_PASSWORD'] = 'fallback_password'
        os.environ['DB_PORT'] = '5433'

        config = db_config()
        
        self.assertEqual(config['default']['USER'], 'testuser')
        self.assertEqual(config['default']['PASSWORD'], 'fallback_password')
        self.assertEqual(config['default']['HOST'], 'testhost')
        self.assertEqual(config['default']['PORT'], '5433')
        self.assertEqual(config['default']['NAME'], 'testdb')

    def test_individual_db_variables(self):
        """Test configuration using individual DB_* environment variables."""
        os.environ['DB_ENGINE'] = 'django.db.backends.mysql'
        os.environ['DB_NAME'] = 'test_db'
        os.environ['DB_USER'] = 'test_user'
        os.environ['DB_PASSWORD'] = 'test_password'
        os.environ['DB_HOST'] = 'test_host'
        os.environ['DB_PORT'] = '3306'

        config = db_config()
        
        self.assertEqual(config['default']['ENGINE'], 'django.db.backends.mysql')
        self.assertEqual(config['default']['NAME'], 'test_db')
        self.assertEqual(config['default']['USER'], 'test_user')
        self.assertEqual(config['default']['PASSWORD'], 'test_password')
        self.assertEqual(config['default']['HOST'], 'test_host')
        self.assertEqual(config['default']['PORT'], '3306')

    def test_individual_db_variables_with_defaults(self):
        """Test individual DB_* variables with default values."""
        os.environ['DB_NAME'] = 'test_db'
        # Don't set DB_HOST and DB_PORT to test defaults

        config = db_config()
        
        self.assertEqual(config['default']['ENGINE'], 'django.db.backends.postgresql')
        self.assertEqual(config['default']['NAME'], 'test_db')
        self.assertEqual(config['default']['HOST'], 'localhost')
        self.assertEqual(config['default']['PORT'], '5432')

    def test_database_engine_detection(self):
        """Test database engine detection from various URL schemes."""
        test_cases = [
            ('postgresql://user:pass@host/db', 'django.db.backends.postgresql'),
            ('postgres://user:pass@host/db', 'django.db.backends.postgresql'),
            ('psql://user:pass@host/db', 'django.db.backends.postgresql'),
            ('mysql://user:pass@host/db', 'django.db.backends.mysql'),
            ('sqlite:///path/to/db.sqlite3', 'django.db.backends.sqlite3'),
            ('unknown://user:pass@host/db', 'django.db.backends.postgresql'),  # Default
        ]

        for url, expected_engine in test_cases:
            with self.subTest(url=url):
                # Clear environment
                for var in os.environ.copy():
                    if var.startswith('DB_') or var == 'DATABASE_URL':
                        del os.environ[var]
                
                os.environ['DATABASE_URL'] = url
                config = db_config()
                self.assertEqual(config['default']['ENGINE'], expected_engine)

    def test_ssl_options_from_environment(self):
        """Test SSL options configuration from environment variables."""
        os.environ['DB_NAME'] = 'test_db'
        os.environ['DB_SSLMODE'] = 'require'
        os.environ['DB_SSLROOTCERT'] = '/path/to/root.crt'
        os.environ['DB_SSLCERT'] = '/path/to/client.crt'
        os.environ['DB_SSLKEY'] = '/path/to/client.key'

        config = db_config()
        
        options = config['default']['OPTIONS']
        self.assertEqual(options['sslmode'], 'require')
        self.assertEqual(options['sslrootcert'], '/path/to/root.crt')
        self.assertEqual(options['sslcert'], '/path/to/client.crt')
        self.assertEqual(options['sslkey'], '/path/to/client.key')

    def test_ssl_options_base64_encoded(self):
        """Test SSL options with base64-encoded certificates."""
        os.environ['DB_NAME'] = 'test_db'
        
        # Create base64-encoded test data
        cert_data = b'-----BEGIN CERTIFICATE-----\ntest_cert_data\n-----END CERTIFICATE-----'
        key_data = b'-----BEGIN PRIVATE KEY-----\ntest_key_data\n-----END PRIVATE KEY-----'
        
        import base64
        os.environ['DB_SSLROOTCERT_B64'] = base64.b64encode(cert_data).decode()
        os.environ['DB_SSLKEY_B64'] = base64.b64encode(key_data).decode()

        with patch('tempfile.mkstemp') as mock_mkstemp, \
             patch('os.fdopen') as mock_fdopen, \
             patch('builtins.open', mock_open()) as mock_file:
            
            # Mock tempfile creation
            mock_mkstemp.side_effect = [(1, '/tmp/db_root.crt'), (2, '/tmp/db_key.key')]
            mock_fdopen.return_value.__enter__.return_value = mock_file.return_value

            config = db_config()
            
            options = config['default']['OPTIONS']
            self.assertEqual(options['sslrootcert'], '/tmp/db_root.crt')
            self.assertEqual(options['sslkey'], '/tmp/db_key.key')

    def test_json_db_options_override(self):
        """Test that DJANGO_DB_OPTIONS JSON takes precedence over individual SSL vars."""
        os.environ['DB_NAME'] = 'test_db'
        os.environ['DB_SSLMODE'] = 'require'  # Should be overridden
        
        json_options = {
            'sslmode': 'prefer',
            'connect_timeout': 30,
            'custom_option': 'value'
        }
        os.environ['DJANGO_DB_OPTIONS'] = json.dumps(json_options)

        config = db_config()
        
        options = config['default']['OPTIONS']
        self.assertEqual(options['sslmode'], 'prefer')  # From JSON, not env var
        self.assertEqual(options['connect_timeout'], 30)
        self.assertEqual(options['custom_option'], 'value')

    def test_invalid_json_db_options(self):
        """Test that invalid JSON in DJANGO_DB_OPTIONS raises ValueError."""
        os.environ['DB_NAME'] = 'test_db'
        os.environ['DJANGO_DB_OPTIONS'] = 'invalid json{'

        with self.assertRaises(ValueError) as cm:
            db_config()
        
        self.assertIn('DJANGO_DB_OPTIONS must be valid JSON', str(cm.exception))

    def test_missing_database_configuration(self):
        """Test that missing database configuration raises ValueError."""
        # Don't set any database environment variables
        
        with self.assertRaises(ValueError) as cm:
            db_config()
        
        self.assertIn('Database configuration missing', str(cm.exception))

    @patch.dict(os.environ, {}, clear=True)
    def test_environment_priority_over_dotenv(self):
        """Test that environment variables take priority over .env file."""
        # Set environment variable
        os.environ['DB_NAME'] = 'env_database'
        os.environ['DB_USER'] = 'env_user'
        
        # Mock .env file content that would conflict
        dotenv_content = """
DB_NAME=dotenv_database
DB_USER=dotenv_user
DB_PASSWORD=dotenv_password
DB_HOST=dotenv_host
"""
        
        with patch('builtins.open', mock_open(read_data=dotenv_content)):
            # In a real scenario, .env would be loaded before calling db_config()
            # Here we simulate that dotenv was already processed but env vars override
            config = db_config()
            
            # Environment variables should take priority
            self.assertEqual(config['default']['NAME'], 'env_database')
            self.assertEqual(config['default']['USER'], 'env_user')

    def test_complete_configuration_structure(self):
        """Test that the returned configuration has the correct structure."""
        os.environ['DATABASE_URL'] = 'postgresql://user:pass@host:5432/dbname'
        
        config = db_config()
        
        # Verify structure
        self.assertIn('default', config)
        default_config = config['default']
        
        required_keys = ['ENGINE', 'NAME', 'USER', 'PASSWORD', 'HOST', 'PORT', 'OPTIONS']
        for key in required_keys:
            self.assertIn(key, default_config)
        
        # Verify types
        self.assertIsInstance(default_config['OPTIONS'], dict)
        self.assertIsInstance(default_config['ENGINE'], str)
        self.assertIsInstance(default_config['PORT'], str)

    def test_empty_database_url_falls_back(self):
        """Test that empty DATABASE_URL falls back to individual variables."""
        os.environ['DATABASE_URL'] = ''  # Empty string
        os.environ['DB_NAME'] = 'fallback_db'
        
        config = db_config()
        
        self.assertEqual(config['default']['NAME'], 'fallback_db')

    def test_sqlite_configuration(self):
        """Test SQLite database configuration."""
        os.environ['DATABASE_URL'] = 'sqlite:///path/to/database.sqlite3'
        
        config = db_config()
        
        self.assertEqual(config['default']['ENGINE'], 'django.db.backends.sqlite3')
        self.assertEqual(config['default']['NAME'], 'path/to/database.sqlite3')


if __name__ == '__main__':
    import unittest
    unittest.main()
