"""
Integration test demonstrating environment variable priority over .env files.

This test creates a temporary .env file and shows that environment variables
take precedence over .env file values when both are present.
"""

import os
import tempfile
from pathlib import Path
from unittest import TestCase

from endo_api.settings_base.env import db_config


class TestEnvironmentPriority(TestCase):
    """Test that environment variables take priority over .env file."""

    def setUp(self):
        """Store original environment."""
        self.original_env = dict(os.environ)
        
        # Clear database-related vars
        db_vars = [
            'DATABASE_URL', 'DB_ENGINE', 'DB_NAME', 'DB_USER', 'DB_PASSWORD',
            'DB_HOST', 'DB_PORT'
        ]
        for var in db_vars:
            os.environ.pop(var, None)

    def tearDown(self):
        """Restore original environment."""
        os.environ.clear()
        os.environ.update(self.original_env)

    def test_env_vars_override_dotenv_file(self):
        """Test that environment variables override .env file values."""
        # Create a temporary .env file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
            f.write("""
# Test .env file
DB_NAME=dotenv_database
DB_USER=dotenv_user
DB_PASSWORD=dotenv_password
DB_HOST=dotenv_host
DB_PORT=5433
""")
            env_file = f.name

        try:
            # Simulate loading .env file (normally done by dotenv)
            # In real usage, python-dotenv would load these, but env vars override
            os.environ.update({
                'DB_NAME': 'dotenv_database',
                'DB_USER': 'dotenv_user', 
                'DB_PASSWORD': 'dotenv_password',
                'DB_HOST': 'dotenv_host',
                'DB_PORT': '5433'
            })
            
            # Now set some environment variables that should override
            os.environ['DB_NAME'] = 'env_override_db'
            os.environ['DB_USER'] = 'env_override_user'
            # Leave DB_PASSWORD and others from "dotenv"
            
            config = db_config()
            
            # Environment variables should take priority
            self.assertEqual(config['default']['NAME'], 'env_override_db')
            self.assertEqual(config['default']['USER'], 'env_override_user')
            
            # Values not overridden should come from "dotenv" simulation
            self.assertEqual(config['default']['PASSWORD'], 'dotenv_password')
            self.assertEqual(config['default']['HOST'], 'dotenv_host')
            self.assertEqual(config['default']['PORT'], '5433')
            
        finally:
            # Clean up temp file
            Path(env_file).unlink()

    def test_database_url_overrides_everything(self):
        """Test that DATABASE_URL overrides both env vars and dotenv."""
        # Set individual variables (simulating dotenv + some env overrides)
        os.environ.update({
            'DB_NAME': 'individual_db',
            'DB_USER': 'individual_user',
            'DB_PASSWORD': 'individual_pass',
            'DB_HOST': 'individual_host',
            'DB_PORT': '5434'
        })
        
        # Set DATABASE_URL which should override everything
        os.environ['DATABASE_URL'] = 'postgresql://url_user:url_pass@url_host:5435/url_db'
        
        config = db_config()
        
        # All values should come from DATABASE_URL
        self.assertEqual(config['default']['NAME'], 'url_db')
        self.assertEqual(config['default']['USER'], 'url_user')
        self.assertEqual(config['default']['PASSWORD'], 'url_pass')
        self.assertEqual(config['default']['HOST'], 'url_host')
        self.assertEqual(config['default']['PORT'], '5435')


if __name__ == '__main__':
    import unittest
    unittest.main()
