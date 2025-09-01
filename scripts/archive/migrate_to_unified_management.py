#!/usr/bin/env python3
"""
Migration script to transition from fragmented management to unified DevEnv system
"""

import os
import sys
import shutil
import subprocess
from pathlib import Path

# Get project root
PROJECT_ROOT = Path(__file__).parent.parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
DEVENV_DIR = PROJECT_ROOT / "devenv"

def print_header(title):
    """Print a formatted header"""
    print(f"\n{'='*60}")
    print(f" {title}")
    print(f"{'='*60}")

def backup_legacy_scripts():
    """Backup legacy management scripts"""
    print_header("Backing Up Legacy Scripts")
    
    backup_dir = PROJECT_ROOT / "legacy_scripts_backup"
    backup_dir.mkdir(exist_ok=True)
    
    legacy_scripts = [
        "docker-manager.sh",
        "config-manager.sh", 
        "container-dev.sh",
        "deploy-prod.sh",
        "switch-mode.sh",
        "docker-cleanup.sh"
    ]
    
    for script in legacy_scripts:
        script_path = PROJECT_ROOT / script
        if script_path.exists():
            backup_path = backup_dir / script
            shutil.copy2(script_path, backup_path)
            print(f"✅ Backed up: {script}")
        else:
            print(f"ℹ️  Not found: {script}")
    
    # Also backup any Python management scripts that aren't in the unified system
    python_scripts = [
        "env_manager.py",
        "config_manager.py", 
        "setup_project.py"
    ]
    
    for script in python_scripts:
        script_path = SCRIPTS_DIR / script
        if script_path.exists():
            backup_path = backup_dir / script
            shutil.copy2(script_path, backup_path)
            print(f"✅ Backed up: scripts/{script}")
    
    print(f"\n📁 Legacy scripts backed up to: {backup_dir}")

def validate_unified_system():
    """Validate that the unified management system is properly configured"""
    print_header("Validating Unified System")
    
    # Check required files exist
    required_files = [
        DEVENV_DIR / "management.nix",
        DEVENV_DIR / "default.nix", 
        PROJECT_ROOT / "app_config.nix"
    ]
    
    all_files_exist = True
    for file_path in required_files:
        if file_path.exists():
            print(f"✅ Found: {file_path.relative_to(PROJECT_ROOT)}")
        else:
            print(f"❌ Missing: {file_path.relative_to(PROJECT_ROOT)}")
            all_files_exist = False
    
    if not all_files_exist:
        print("\n❌ Required files missing! Please ensure all files are created.")
        return False
    
    print("\n🎯 Testing DevEnv commands...")
    
    # Test basic DevEnv functionality
    test_commands = [
        ["devenv", "--version"],
        ["devenv", "task", "list"],
        ["devenv", "script", "--help"]
    ]
    
    for cmd in test_commands:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_ROOT)
            if result.returncode == 0:
                print(f"✅ Command works: {' '.join(cmd)}")
            else:
                print(f"⚠️  Command issue: {' '.join(cmd)} (exit code: {result.returncode})")
        except FileNotFoundError:
            print(f"❌ Command not found: {' '.join(cmd)}")
            return False
    
    return True

def show_usage_guide():
    """Show the new usage guide"""
    print_header("New Unified Management System Usage")
    
    print("""
🎯 CENTRALIZED MANAGEMENT COMMANDS

Main Management Interface:
  manage setup      - Complete environment setup
  manage dev        - Switch to development mode  
  manage prod       - Switch to production mode
  manage build      - Build container for current mode
  manage run        - Run container for current mode
  manage stop       - Stop containers
  manage restart    - Restart containers
  manage clean      - Clean up containers and images
  manage deploy     - Full deployment pipeline
  manage status     - Show current status

Server Management:
  run-server                - Start server (mode-aware)
  run-server-container      - Start server (for containers)

Individual Tasks (via devenv task run):
  env:setup                 - Environment setup
  env:setup-cuda           - CUDA environment setup
  container:build          - Build containers
  container:run            - Run containers
  container:stop           - Stop containers
  container:remove         - Remove containers
  container:cleanup        - Clean up everything
  db:migrate               - Database migrations
  db:load-data            - Load database data
  db:collectstatic        - Collect static files
  deploy:full             - Complete deployment

WORKFLOW EXAMPLES:

Development Workflow:
  manage dev              # Switch to dev mode
  manage setup           # Setup environment
  manage build           # Build dev container
  manage run             # Run dev container

Production Workflow:
  manage prod            # Switch to prod mode  
  manage setup           # Setup environment
  manage deploy          # Full deployment pipeline

Container Management:
  manage status          # Check current state
  manage clean           # Clean everything
  manage build           # Rebuild containers
  manage restart         # Restart services

WHAT REPLACED WHAT:

Legacy Command              → New Command
├─ docker-manager.sh       → manage build/run/stop/clean
├─ container-dev.sh        → manage dev + manage build/run
├─ deploy-prod.sh          → manage prod + manage deploy
├─ switch-mode.sh          → manage dev/prod
├─ env_manager.py          → devenv task run env:setup
├─ config_manager.py       → devenv task run env:setup
└─ setup_project.py        → manage setup

""")

def create_migration_aliases():
    """Create temporary alias script for legacy compatibility"""
    print_header("Creating Legacy Compatibility Aliases")
    
    alias_script = PROJECT_ROOT / "legacy_aliases.sh"
    
    aliases_content = """#!/bin/bash
# Legacy compatibility aliases for unified management system
# Source this file to get legacy command compatibility: source legacy_aliases.sh

echo "🔄 Loading legacy compatibility aliases..."
echo "⚠️  These aliases will be deprecated. Please migrate to 'manage' commands."

# Container management aliases
alias docker-manager.sh='echo "⚠️  Deprecated: Use manage commands instead"; manage'
alias container-dev.sh='echo "⚠️  Deprecated: Use manage dev && manage build && manage run"; manage dev && manage build && manage run'
alias deploy-prod.sh='echo "⚠️  Deprecated: Use manage prod && manage deploy"; manage prod && manage deploy'
alias switch-mode.sh='echo "⚠️  Deprecated: Use manage dev/prod"; manage'

# Python script aliases  
alias env_manager.py='echo "⚠️  Deprecated: Use devenv task run env:setup"; devenv task run env:setup'
alias config_manager.py='echo "⚠️  Deprecated: Use devenv task run env:setup"; devenv task run env:setup'
alias setup_project.py='echo "⚠️  Deprecated: Use manage setup"; manage setup'

echo "✅ Legacy aliases loaded. Use 'manage help' for new commands."
"""
    
    alias_script.write_text(aliases_content)
    alias_script.chmod(0o755)
    
    print(f"✅ Created: {alias_script.relative_to(PROJECT_ROOT)}")
    print("   Usage: source legacy_aliases.sh")

def main():
    """Main migration function"""
    print_header("Endo API Management System Migration")
    print("Transitioning from fragmented scripts to unified DevEnv management")
    
    # Step 1: Backup legacy scripts
    backup_legacy_scripts()
    
    # Step 2: Validate new system
    if not validate_unified_system():
        print("\n❌ Migration failed: Unified system not ready")
        sys.exit(1)
    
    # Step 3: Create compatibility aliases
    create_migration_aliases()
    
    # Step 4: Show usage guide
    show_usage_guide()
    
    print_header("Migration Complete!")
    print("""
✅ Migration successful!

NEXT STEPS:
1. Test the new system: manage setup
2. Try development workflow: manage dev && manage build && manage run
3. Check status: manage status  
4. For legacy compatibility: source legacy_aliases.sh

CLEANUP (when ready):
- Remove legacy_scripts_backup/ after confirming everything works
- Remove legacy_aliases.sh when fully migrated
- Update any CI/CD scripts to use new commands

📚 For help: manage help
🐛 Issues? Check: devenv task list
    """)

if __name__ == "__main__":
    main()
