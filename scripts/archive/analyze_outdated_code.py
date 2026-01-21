#!/usr/bin/env python3
"""
Outdated Code Analysis and Cleanup Tool for Endo API
=====================================================

This script analyzes the codebase to identify outdated, unused, and deprecated files
and code patterns that can be safely removed after the unified management migration.
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple
import json
import re
import subprocess
from dataclasses import dataclass, asdict
from datetime import datetime

# Get project root
PROJECT_ROOT = Path(__file__).parent.parent
DEVENV_DIR = PROJECT_ROOT / "devenv"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"

@dataclass
class CleanupItem:
    """Represents an item to be cleaned up"""
    path: Path
    item_type: str  # 'file', 'directory', 'code_pattern', 'config'
    category: str   # 'deprecated', 'unused', 'duplicate', 'outdated'
    reason: str
    risk_level: str  # 'low', 'medium', 'high'
    replacement: str = ""
    backup_needed: bool = False

class CodebaseAnalyzer:
    """Analyzes the codebase for cleanup opportunities"""
    
    def __init__(self):
        self.cleanup_items: List[CleanupItem] = []
        self.file_patterns = self._load_patterns()
        
    def _load_patterns(self) -> Dict:
        """Load patterns for identifying outdated code"""
        return {
            'deprecated_files': [
                '*.bak', '*.backup', '*.old', '*.orig',
                'docker-compose.yml', 'docker-compose.prod.yml',
                'env_setup.py', 'make_conf.py'
            ],
            'deprecated_scripts': [
                'docker-manager.sh', 'container-dev.sh', 'deploy-prod.sh', 
                'switch-mode.sh', 'config-manager.sh', 'docker-cleanup.sh'
            ],
            'deprecated_patterns': [
                r'DEPRECATED',
                r'TODO.*remove',
                r'FIXME.*remove', 
                r'Legacy.*deprecated',
                r'Use.*instead'
            ],
            'unused_dockerfiles': [
                'Dockerfile.dev', 'Dockerfile.prod'
            ]
        }

    def analyze_deprecated_files(self):
        """Find files explicitly marked as deprecated"""
        print("🔍 Analyzing deprecated files...")
        
        # Check for docker-compose files
        compose_files = [
            PROJECT_ROOT / "docker-compose.yml",
            PROJECT_ROOT / "docker-compose.prod.yml"
        ]
        
        for compose_file in compose_files:
            if compose_file.exists():
                content = compose_file.read_text()
                if "DEPRECATED" in content:
                    self.cleanup_items.append(CleanupItem(
                        path=compose_file,
                        item_type="file",
                        category="deprecated", 
                        reason="Explicitly marked as deprecated in favor of docker-manager.sh generated configs",
                        risk_level="low",
                        replacement="Use docker-manager.sh to generate up-to-date configurations",
                        backup_needed=True
                    ))

    def analyze_legacy_scripts(self):
        """Find legacy shell scripts that have been replaced"""
        print("🔍 Analyzing legacy scripts...")
        
        legacy_scripts = {
            'docker-manager.sh': 'manage build/run/stop/clean commands',
            'container-dev.sh': 'manage dev && manage build && manage run',
            'deploy-prod.sh': 'manage prod && manage deploy',
            'switch-mode.sh': 'manage dev/prod commands',
            'config-manager.sh': 'manage setup command',
            'docker-cleanup.sh': 'docker system prune or manage clean'
        }
        
        for script_name, replacement in legacy_scripts.items():
            script_path = PROJECT_ROOT / script_name
            if script_path.exists():
                # Check if still actively used (not backed up)
                backup_path = PROJECT_ROOT / "legacy_scripts_backup" / script_name
                if backup_path.exists():
                    self.cleanup_items.append(CleanupItem(
                        path=script_path,
                        item_type="file",
                        category="deprecated",
                        reason=f"Replaced by unified management system: {replacement}",
                        risk_level="medium",
                        replacement=replacement,
                        backup_needed=False  # Already backed up
                    ))

    def analyze_python_legacy_scripts(self):
        """Find legacy Python scripts in scripts/ directory"""
        print("🔍 Analyzing legacy Python scripts...")
        
        legacy_python = {
            'env_manager.py': 'manage setup command',
            'config_manager.py': 'manage setup command', 
            'setup_project.py': 'manage setup command',
            'make_conf.py': 'manage setup command (if exists)',
            'env_setup.py': 'manage setup command (if exists)'
        }
        
        for script_name, replacement in legacy_python.items():
            script_path = SCRIPTS_DIR / script_name
            if script_path.exists():
                backup_path = PROJECT_ROOT / "legacy_scripts_backup" / script_name
                if backup_path.exists():
                    self.cleanup_items.append(CleanupItem(
                        path=script_path,
                        item_type="file", 
                        category="deprecated",
                        reason=f"Replaced by unified management: {replacement}",
                        risk_level="low",
                        replacement=replacement,
                        backup_needed=False
                    ))

    def analyze_dockerfile_usage(self):
        """Analyze Dockerfile usage now that we have DevEnv containers"""
        print("🔍 Analyzing Dockerfile usage...")
        
        dockerfiles = [
            PROJECT_ROOT / "Dockerfile.dev",
            PROJECT_ROOT / "Dockerfile.prod"
        ]
        
        for dockerfile in dockerfiles:
            if dockerfile.exists():
                # Check if DevEnv containers are being used instead
                devenv_containers_exist = (DEVENV_DIR / "containers.nix").exists()
                if devenv_containers_exist:
                    self.cleanup_items.append(CleanupItem(
                        path=dockerfile,
                        item_type="file",
                        category="potentially_unused",
                        reason="DevEnv native containers may replace traditional Dockerfiles",
                        risk_level="high",  # Keep for now, needs manual verification
                        replacement="DevEnv containers in devenv/containers.nix",
                        backup_needed=True
                    ))

    def analyze_deprecated_code_patterns(self):
        """Find code patterns marked as deprecated"""
        print("🔍 Analyzing deprecated code patterns...")
        
        # Search for deprecated patterns in .nix files
        nix_files = list(DEVENV_DIR.glob("*.nix"))
        
        for nix_file in nix_files:
            try:
                content = nix_file.read_text()
                lines = content.split('\n')
                
                for i, line in enumerate(lines, 1):
                    if any(re.search(pattern, line, re.IGNORECASE) for pattern in self.file_patterns['deprecated_patterns']):
                        # Find the deprecated command/function
                        if 'deprecatedCommand' in line or 'DEPRECATED:' in line:
                            self.cleanup_items.append(CleanupItem(
                                path=nix_file,
                                item_type="code_pattern",
                                category="deprecated",
                                reason=f"Deprecated code pattern on line {i}: {line.strip()}",
                                risk_level="low",
                                replacement="Check surrounding context for new implementation",
                                backup_needed=False
                            ))
            except Exception as e:
                print(f"Warning: Could not analyze {nix_file}: {e}")

    def analyze_test_scripts(self):
        """Find test scripts that may be outdated"""
        print("🔍 Analyzing test scripts...")
        
        test_scripts = list(PROJECT_ROOT.glob("test-*.sh"))
        test_scripts.extend(PROJECT_ROOT.glob("*test*.sh"))
        
        for script in test_scripts:
            if script.exists():
                try:
                    content = script.read_text()
                    if any(legacy in content for legacy in ['docker-manager.sh', 'container-dev.sh', 'deploy-prod.sh']):
                        self.cleanup_items.append(CleanupItem(
                            path=script,
                            item_type="file",
                            category="outdated",
                            reason="Test script references legacy management commands",
                            risk_level="medium",
                            replacement="Update to use 'manage' commands",
                            backup_needed=True
                        ))
                except Exception as e:
                    print(f"Warning: Could not analyze {script}: {e}")

    def analyze_backup_directories(self):
        """Find backup directories that can be cleaned up"""
        print("🔍 Analyzing backup directories...")
        
        backup_dirs = [
            PROJECT_ROOT / "legacy_scripts_backup"
        ]
        
        for backup_dir in backup_dirs:
            if backup_dir.exists() and backup_dir.is_dir():
                # Check age and if migration is complete
                files_count = len(list(backup_dir.glob("*")))
                self.cleanup_items.append(CleanupItem(
                    path=backup_dir,
                    item_type="directory",
                    category="backup",
                    reason=f"Backup directory with {files_count} files from migration",
                    risk_level="low",
                    replacement="Can be removed after verifying unified system works",
                    backup_needed=False
                ))

    def analyze_compatibility_files(self):
        """Find temporary compatibility files"""
        print("🔍 Analyzing compatibility files...")
        
        compat_files = [
            PROJECT_ROOT / "legacy_aliases.sh"
        ]
        
        for compat_file in compat_files:
            if compat_file.exists():
                self.cleanup_items.append(CleanupItem(
                    path=compat_file,
                    item_type="file",
                    category="temporary",
                    reason="Temporary compatibility file for migration period",
                    risk_level="low", 
                    replacement="Remove after full migration to unified commands",
                    backup_needed=False
                ))

    def check_file_usage(self, file_path: Path) -> Tuple[bool, List[str]]:
        """Check if a file is still being used by searching for references"""
        references = []
        
        # Search for references in key files
        search_paths = [
            PROJECT_ROOT / "README.md",
            PROJECT_ROOT / "*.sh",
            DEVENV_DIR,
            SCRIPTS_DIR
        ]
        
        file_name = file_path.name
        try:
            result = subprocess.run([
                "grep", "-r", file_name, str(PROJECT_ROOT)
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                references = result.stdout.strip().split('\n')
                # Filter out the file referencing itself
                references = [ref for ref in references if file_name not in ref.split(':')[0]]
        except Exception:
            pass
        
        return len(references) > 0, references

    def run_analysis(self):
        """Run complete analysis"""
        print("🔍 Starting comprehensive codebase analysis...")
        print("=" * 60)
        
        self.analyze_deprecated_files()
        self.analyze_legacy_scripts()
        self.analyze_python_legacy_scripts()
        self.analyze_dockerfile_usage()
        self.analyze_deprecated_code_patterns()
        self.analyze_test_scripts()
        self.analyze_backup_directories()
        self.analyze_compatibility_files()
        
        print(f"\n✅ Analysis complete! Found {len(self.cleanup_items)} items for review.")

    def generate_report(self) -> str:
        """Generate detailed cleanup report"""
        report = []
        report.append("# Endo API Cleanup Analysis Report")
        report.append("=" * 50)
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append(f"Total items found: {len(self.cleanup_items)}")
        report.append("")
        
        # Group by category
        by_category = {}
        for item in self.cleanup_items:
            if item.category not in by_category:
                by_category[item.category] = []
            by_category[item.category].append(item)
        
        for category, items in by_category.items():
            report.append(f"## {category.upper()} ({len(items)} items)")
            report.append("")
            
            # Group by risk level
            by_risk = {'low': [], 'medium': [], 'high': []}
            for item in items:
                by_risk[item.risk_level].append(item)
                
            for risk in ['low', 'medium', 'high']:
                if by_risk[risk]:
                    report.append(f"### {risk.upper()} RISK ({len(by_risk[risk])} items)")
                    report.append("")
                    
                    for item in by_risk[risk]:
                        report.append(f"**{item.path.relative_to(PROJECT_ROOT)}**")
                        report.append(f"- Type: {item.item_type}")
                        report.append(f"- Reason: {item.reason}")
                        if item.replacement:
                            report.append(f"- Replacement: {item.replacement}")
                        report.append(f"- Backup needed: {'Yes' if item.backup_needed else 'No'}")
                        report.append("")
        
        return "\n".join(report)

    def generate_cleanup_script(self) -> str:
        """Generate executable cleanup script"""
        script = []
        script.append("#!/usr/bin/env bash")
        script.append("# Automated cleanup script for Endo API")
        script.append("# Generated by outdated code analysis")
        script.append("")
        script.append("set -e")
        script.append("")
        script.append("echo '🧹 Endo API Cleanup Script'")
        script.append("echo '=========================='")
        script.append("")
        
        # Group by risk level for safe execution
        by_risk = {'low': [], 'medium': [], 'high': []}
        for item in self.cleanup_items:
            by_risk[item.risk_level].append(item)
        
        # Low risk items - can be automated
        if by_risk['low']:
            script.append("echo '🟢 Processing LOW RISK items (automated)...'")
            script.append("")
            
            for item in by_risk['low']:
                if item.category == 'backup':
                    continue  # Skip backup dirs for now
                    
                rel_path = item.path.relative_to(PROJECT_ROOT)
                if item.item_type == 'file':
                    script.append(f"if [ -f '{rel_path}' ]; then")
                    script.append(f"  echo '  Removing: {rel_path}'")
                    script.append(f"  rm '{rel_path}'")
                    script.append(f"fi")
                elif item.item_type == 'directory':
                    script.append(f"if [ -d '{rel_path}' ]; then")
                    script.append(f"  echo '  Removing directory: {rel_path}'")
                    script.append(f"  rm -rf '{rel_path}'")
                    script.append(f"fi")
                script.append("")
        
        # Medium/High risk items - require confirmation
        for risk in ['medium', 'high']:
            if by_risk[risk]:
                script.append(f"echo '🟡 {risk.upper()} RISK items (requires confirmation):'")
                script.append("")
                
                for item in by_risk[risk]:
                    rel_path = item.path.relative_to(PROJECT_ROOT)
                    script.append(f"echo 'Item: {rel_path}'")
                    script.append(f"echo '  Reason: {item.reason}'")
                    script.append(f"echo '  Replacement: {item.replacement}'")
                    script.append(f"read -p 'Remove this item? [y/N]: ' -n 1 -r")
                    script.append(f"echo")
                    script.append(f"if [[ $REPLY =~ ^[Yy]$ ]]; then")
                    
                    if item.backup_needed:
                        script.append(f"  echo '  Creating backup...'")
                        script.append(f"  cp '{rel_path}' '{rel_path}.backup-$(date +%Y%m%d)'")
                    
                    if item.item_type == 'file':
                        script.append(f"  rm '{rel_path}'")
                    elif item.item_type == 'directory':
                        script.append(f"  rm -rf '{rel_path}'")
                    
                    script.append(f"  echo '  ✅ Removed {rel_path}'")
                    script.append(f"else")
                    script.append(f"  echo '  ⏭️  Skipped {rel_path}'")
                    script.append(f"fi")
                    script.append("")
        
        script.append("echo '✅ Cleanup complete!'")
        
        return "\n".join(script)

def main():
    """Main execution function"""
    print("🔍 Endo API Outdated Code Analysis")
    print("=" * 40)
    
    analyzer = CodebaseAnalyzer()
    analyzer.run_analysis()
    
    # Generate report
    report = analyzer.generate_report()
    report_file = PROJECT_ROOT / "CLEANUP_ANALYSIS_REPORT.md"
    report_file.write_text(report)
    print(f"\n📊 Report saved to: {report_file}")
    
    # Generate cleanup script
    script = analyzer.generate_cleanup_script()
    script_file = PROJECT_ROOT / "cleanup_outdated_code.sh"
    script_file.write_text(script)
    script_file.chmod(0o755)
    print(f"🧹 Cleanup script saved to: {script_file}")
    
    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    by_category = {}
    by_risk = {}
    
    for item in analyzer.cleanup_items:
        by_category[item.category] = by_category.get(item.category, 0) + 1
        by_risk[item.risk_level] = by_risk.get(item.risk_level, 0) + 1
    
    print(f"📊 Total items: {len(analyzer.cleanup_items)}")
    print("\nBy Category:")
    for category, count in by_category.items():
        print(f"  {category}: {count}")
    
    print("\nBy Risk Level:")
    for risk, count in by_risk.items():
        print(f"  {risk}: {count}")
    
    print(f"\n📖 Next Steps:")
    print(f"1. Review report: {report_file}")
    print(f"2. Run cleanup script: ./{script_file.name}")
    print(f"3. Test system after cleanup")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
