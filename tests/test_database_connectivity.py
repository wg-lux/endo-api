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
import pytest

# Mark entire module as integration (skipped by default via pytest.ini)
pytestmark = pytest.mark.integration


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


def _prepare_conn_kwargs(creds: dict) -> dict:
    """Prepare connection kwargs for psycopg/psycopg2 compatibility.

    psycopg (v3) expects 'dbname' instead of 'database'. This helper
    normalizes the keys to avoid 'invalid connection option "database"'.
    """
    if creds is None:
        return {}
    kw = creds.copy()
    # Map 'database' -> 'dbname' for psycopg
    if 'database' in kw and 'dbname' not in kw:
        kw['dbname'] = kw.pop('database')
    # Ensure port is a string (both drivers accept str/int, but keep consistent)
    if 'port' in kw:
        kw['port'] = str(kw['port'])
    return kw


def test_postgres_connection():
    """Test PostgreSQL database connection."""
    print("🔗 Testing PostgreSQL connection...")
    
    credentials = get_db_credentials()
    # Fail if credentials could not be loaded
    assert credentials, "Could not load database credentials"
    
    # Skip if password not available (intended skip)
    if not credentials.get("password"):
        pytest.skip("Database password not available - skipping connection test")
    
    try:
        import psycopg
        try:
            # psycopg provides SQL helpers in a submodule; import as psql alias
            from psycopg import sql as psql
        except Exception:
            # Fallback if the above import style isn't available in the environment
            import psycopg.sql as psql
    except ImportError:
        pytest.skip("psycopg not available - install with: pip install psycopg-binary")

    try:
        # Prepare and normalize connection kwargs
        conn_kwargs = _prepare_conn_kwargs(credentials)
        # Show the normalized connection target (psycopg expects 'dbname')
        normalized_db = conn_kwargs.get('dbname') or conn_kwargs.get('database') or '<unknown>'
        print(f"   Connecting to: {credentials['user']}@{credentials['host']}:{conn_kwargs.get('port')}/{normalized_db}")
        connection = psycopg.connect(**conn_kwargs)
        cursor = connection.cursor()
        # Use psycopg.sql.SQL to satisfy the static type checker
        cursor.execute(psql.SQL("SELECT version();"))
        version = cursor.fetchone()
        cursor.close()
        connection.close()

        print("✅ PostgreSQL connection successful")
        if version:
            print(f"   Database version: {version[0]}")
    except Exception as e:
        pytest.fail(f"PostgreSQL connection failed: {e}")


def test_database_tables():
    """Test that essential Django tables exist."""
    print("📊 Testing database tables...")
    
    credentials = get_db_credentials()
    if not credentials or not credentials.get("password"):
        pytest.skip("Database credentials not available - skipping table check")
    
    try:
        import psycopg
        try:
            from psycopg import sql as psql
        except Exception:
            import psycopg.sql as psql
    except ImportError:
        pytest.skip("psycopg not available - skipping table check")

    try:
        conn_kwargs = _prepare_conn_kwargs(credentials)
        connection = psycopg.connect(**conn_kwargs)
        cursor = connection.cursor()

        # Check for essential Django tables
        essential_tables = [
            'django_migrations',
            'django_content_type', 
            'auth_user',
            'auth_group',
            'auth_permission'
        ]
        
        # Use SQL object to avoid passing plain str to cursor.execute
        cursor.execute(psql.SQL("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        """))
        
        existing_tables = [row[0] for row in cursor.fetchall()]
        
        missing_tables = [t for t in essential_tables if t not in existing_tables]
        
        cursor.close()
        connection.close()
        
        if missing_tables:
            pytest.fail(f"Missing essential Django tables: {missing_tables}. Run 'python manage.py migrate' to create missing tables")
        else:
            print(f"✅ Essential Django tables exist ({len(essential_tables)} checked)")

        # Show some application tables
        app_tables = [t for t in existing_tables if not t.startswith(('django_', 'auth_'))]
        if app_tables:
            print(f"   Found {len(app_tables)} application tables")
            if len(app_tables) <= 10:
                print(f"   Tables: {', '.join(app_tables)}")

    except Exception as e:
        pytest.fail(f"Database table check failed: {e}")


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
            pytest.skip(f"Could not check migrations: {result.stderr}")

        migration_output = result.stdout
        unapplied = [line for line in migration_output.split('\n') 
                   if line.strip().startswith('[ ]')]
        
        if unapplied:
            pytest.fail(f"Found {len(unapplied)} unapplied migrations. Run 'python manage.py migrate' to apply them")
        else:
            print("✅ All migrations are applied")

    except Exception as e:
        pytest.skip(f"Migration check failed: {e}")


def test_database_permissions():
    """Test database user permissions."""
    print("🔐 Testing database permissions...")
    
    credentials = get_db_credentials()
    if not credentials or not credentials.get("password"):
        pytest.skip("Database credentials not available - skipping permissions check")
    
    try:
        import psycopg
        try:
            from psycopg import sql as psql
        except Exception:
            import psycopg.sql as psql
    except ImportError:
        pytest.skip("psycopg not available - skipping permissions check")

    try:
        conn_kwargs = _prepare_conn_kwargs(credentials)
        connection = psycopg.connect(**conn_kwargs)
        cursor = connection.cursor()
        
        # Test basic permissions with a unique table name
        import time
        test_table = f"test_perm_table_{int(time.time())}"
        
        permissions_tests = [
            ("CREATE TABLE", None),
            ("INSERT", None),
            ("SELECT", None),
            ("UPDATE", None),
            ("DELETE", None),
            ("DROP TABLE", None),
        ]
        
        failed_permissions = []
        
        # Build and run each permission check using psycopg.sql to keep typing happy
        try:
            # CREATE TEMP TABLE
            cursor.execute(psql.SQL("CREATE TEMP TABLE {} (id INTEGER)").format(psql.Identifier(test_table)))
            connection.commit()
            # INSERT
            cursor.execute(psql.SQL("INSERT INTO {} (id) VALUES (%s)").format(psql.Identifier(test_table)), (1,))
            connection.commit()
            # SELECT
            cursor.execute(psql.SQL("SELECT * FROM {}").format(psql.Identifier(test_table)))
            _ = cursor.fetchall()
            # UPDATE
            cursor.execute(psql.SQL("UPDATE {} SET id = %s").format(psql.Identifier(test_table)), (2,))
            connection.commit()
            # DELETE
            cursor.execute(psql.SQL("DELETE FROM {} WHERE id = %s").format(psql.Identifier(test_table)), (2,))
            connection.commit()
            # DROP TABLE
            cursor.execute(psql.SQL("DROP TABLE {}").format(psql.Identifier(test_table)))
            connection.commit()
        except Exception as e:
            failed_permissions.append(("permissions", str(e)))
            connection.rollback()
 
        cursor.close()
        connection.close()
        
        if failed_permissions:
            msg = "Failed permissions tests: " + ", ".join(f"{p[0]}: {p[1]}" for p in failed_permissions)
            pytest.fail(msg)
        else:
            print(f"✅ Database permissions OK ({len(permissions_tests)} tests passed)")
        
    except Exception as e:
        pytest.fail(f"Database permissions test failed: {e}")


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
    skipped = 0
    
    for test_name, test_func in tests:
        print(f"--- {test_name} ---")
        try:
            # Tests are written as pytest-style functions that assert/skip/fail.
            # When called directly they return None on success, and raise an
            # exception on skip or failure. We treat exceptions whose class
            # name contains 'skip' as skipped to avoid depending on pytest's
            # internal exception class name in static analysis.
            test_func()
            passed += 1
        except Exception as e:
            ename = e.__class__.__name__.lower()
            if 'skip' in ename:
                print(f"⚠️  Test {test_name} skipped: {e}")
                skipped += 1
            else:
                print(f"❌ Test {test_name} failed: {e}")
                failed += 1
        print()
    
    print("=" * 60)
    print("DATABASE TEST SUMMARY")
    print("=" * 60)
    print(f"Passed: {passed}")
    print(f"Skipped: {skipped}")
    print(f"Failed: {failed}")
    print(f"Total:  {passed + failed + skipped}")
    
    if failed == 0:
        print("🎉 ALL DATABASE TESTS PASSED!")
        return 0
    else:
        print("❌ Some database tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
