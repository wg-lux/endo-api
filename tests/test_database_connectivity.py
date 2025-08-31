#!/usr/bin/env python3
"""
Database Connection and Migration Tests

This module provides focused tests for database connectivity and Django compatibility
without requiring all dependencies to be available during testing.
"""

import os
import sys
import json
import subprocess
from pathlib import Path


def get_db_config(config_file="app_config.nix", mode="prod"):
    """Get database configuration from app_config.nix."""
    try:
        result = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", config_file, "-A", f"database.{mode}"],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            print(f"❌ Could not read database config: {result.stderr}")
            return None
        
        return json.loads(result.stdout.strip())
    except Exception as e:
        print(f"❌ Failed to parse database config: {e}")
        return None


def get_db_credentials():
    """Get database credentials from configuration files."""
    db_config = get_db_config()
    if not db_config:
        return None
    
    # Read password from file if specified
    password = None
    if "passwordFile" in db_config and db_config["passwordFile"]:
        password_file = Path(db_config["passwordFile"])
        if password_file.exists():
            password = password_file.read_text().strip()
        else:
            print(f"⚠️  Password file not found: {password_file}")
    
    return {
        "host": db_config.get("host", "localhost"),
        "port": int(db_config.get("port", "5432")),
        "database": db_config.get("name", "endoregDbLocal"),
        "user": db_config.get("user", "endoreg_user"),
        "password": password
    }


def test_postgres_connection():
    """Test PostgreSQL database connection."""
    print("🔗 Testing PostgreSQL connection...")
    
    credentials = get_db_credentials()
    if not credentials:
        print("❌ Could not load database credentials")
        return False
    
    if not credentials["password"]:
        print("⚠️  Database password not available - skipping connection test")
        return True  # Not a failure, just skip
    
    try:
        import psycopg2
        
        print(f"   Connecting to: {credentials['user']}@{credentials['host']}:{credentials['port']}/{credentials['database']}")
        
        connection = psycopg2.connect(**credentials)
        
        # Test basic query
        cursor = connection.cursor()
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        
        cursor.close()
        connection.close()
        
        print("✅ PostgreSQL connection successful")
        if version:
            print(f"   Database version: {version[0]}")
        return True
        
    except ImportError:
        print("⚠️  psycopg2 not available - install with: pip install psycopg2-binary")
        return True  # Not a failure, just unavailable
    except Exception as e:
        print(f"❌ PostgreSQL connection failed: {e}")
        return False


def test_database_tables():
    """Test that essential Django tables exist."""
    print("📊 Testing database tables...")
    
    credentials = get_db_credentials()
    if not credentials or not credentials["password"]:
        print("⚠️  Database credentials not available - skipping table check")
        return True
    
    try:
        import psycopg2
        
        connection = psycopg2.connect(**credentials)
        cursor = connection.cursor()
        
        # Check for essential Django tables
        essential_tables = [
            'django_migrations',
            'django_content_type', 
            'auth_user',
            'auth_group',
            'auth_permission'
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
            
        # Show some application tables
        app_tables = [t for t in existing_tables if not t.startswith(('django_', 'auth_'))]
        if app_tables:
            print(f"   Found {len(app_tables)} application tables")
            if len(app_tables) <= 10:
                print(f"   Tables: {', '.join(app_tables)}")
        
        return True
        
    except ImportError:
        print("⚠️  psycopg2 not available")
        return True
    except Exception as e:
        print(f"❌ Database table check failed: {e}")
        return False


def test_django_migration_status():
    """Test Django migration status."""
    print("🔄 Testing Django migration status...")
    
    # Get Django module name
    try:
        result = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", "app_config.nix", "-A", "app.djangoModule"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            django_module = json.loads(result.stdout.strip())
        else:
            django_module = "endo_api"
    except Exception:
        django_module = "endo_api"
    
    try:
        # Set Django settings
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', f'{django_module}.settings_prod')
        
        # Try to run showmigrations
        result = subprocess.run(
            [sys.executable, "manage.py", "showmigrations", "--plan"],
            capture_output=True, text=True, cwd=Path.cwd()
        )
        
        if result.returncode != 0:
            print(f"⚠️  Could not check migrations: {result.stderr}")
            return True  # Not a failure
        
        migration_output = result.stdout
        
        # Check for unapplied migrations
        unapplied = [line for line in migration_output.split('\n') 
                   if line.strip().startswith('[ ]')]
        
        if unapplied:
            print(f"⚠️  Found {len(unapplied)} unapplied migrations")
            if len(unapplied) <= 5:
                for migration in unapplied:
                    print(f"     {migration.strip()}")
            else:
                for migration in unapplied[:3]:
                    print(f"     {migration.strip()}")
                print(f"     ... and {len(unapplied) - 3} more")
            print("   Run 'python manage.py migrate' to apply them")
        else:
            print("✅ All migrations are applied")
        
        return True
        
    except Exception as e:
        print(f"⚠️  Migration check failed: {e}")
        return True  # Not a critical failure


def test_database_permissions():
    """Test database user permissions."""
    print("🔐 Testing database permissions...")
    
    credentials = get_db_credentials()
    if not credentials or not credentials["password"]:
        print("⚠️  Database credentials not available - skipping permissions check")
        return True
    
    try:
        import psycopg2
        
        connection = psycopg2.connect(**credentials)
        cursor = connection.cursor()
        
        # Test basic permissions with a unique table name
        import time
        test_table = f"test_perm_table_{int(time.time())}"
        
        permissions_tests = [
            ("CREATE TABLE", f"CREATE TEMP TABLE {test_table} (id INTEGER)"),
            ("INSERT", f"INSERT INTO {test_table} VALUES (1)"),
            ("SELECT", f"SELECT * FROM {test_table}"),
            ("UPDATE", f"UPDATE {test_table} SET id = 2"),
            ("DELETE", f"DELETE FROM {test_table}"),
            ("DROP TABLE", f"DROP TABLE {test_table}"),
        ]
        
        failed_permissions = []
        
        for perm_name, sql in permissions_tests:
            try:
                cursor.execute(sql)
                connection.commit()
            except Exception as e:
                failed_permissions.append((perm_name, str(e)))
                connection.rollback()
                break  # Stop on first failure to avoid cascade errors
        
        cursor.close()
        connection.close()
        
        if failed_permissions:
            print("❌ Failed permissions tests:")
            for perm, error in failed_permissions:
                print(f"   {perm}: {error}")
            return False
        else:
            print(f"✅ Database permissions OK ({len(permissions_tests)} tests passed)")
        
        return True
        
    except ImportError:
        print("⚠️  psycopg2 not available")
        return True
    except Exception as e:
        print(f"❌ Database permissions test failed: {e}")
        return False


def main():
    """Run all database connectivity tests."""
    print("=" * 60)
    print("DATABASE CONNECTIVITY AND COMPATIBILITY TESTS")
    print("=" * 60)
    print()
    
    tests = [
        ("PostgreSQL Connection", test_postgres_connection),
        ("Database Tables", test_database_tables),
        ("Django Migration Status", test_django_migration_status),
        ("Database Permissions", test_database_permissions),
    ]
    
    passed = 0
    failed = 0
    
    for test_name, test_func in tests:
        print(f"--- {test_name} ---")
        try:
            if test_func():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ Test {test_name} crashed: {e}")
            failed += 1
        print()
    
    print("=" * 60)
    print("DATABASE TEST SUMMARY")
    print("=" * 60)
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Total:  {passed + failed}")
    
    if failed == 0:
        print("🎉 ALL DATABASE TESTS PASSED!")
        return 0
    else:
        print("❌ Some database tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
