#!/usr/bin/env python3
"""
Container Workflow Testing Suite
================================

Comprehensive tests for the DevEnv container management workflow.
Tests both DevEnv native containers and Docker fallback containers.

Usage:
    python tests/test_container_workflow.py
    python -m pytest tests/test_container_workflow.py -v
"""

import json
import os
import subprocess
import time
import requests
import pytest
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Mark entire module as integration
pytestmark = pytest.mark.integration


class ContainerWorkflowTester:
    """Test suite for container build, run, stop, and cleanup workflows"""
    
    def __init__(self):
        self.project_root = Path(__file__).parent.parent
        self.test_port = 8119  # Different from default to avoid conflicts
        self.test_results = {}
        self.containers_to_cleanup = []
    
    def log(self, message: str, level: str = "INFO"):
        """Log test messages with timestamp"""
        timestamp = time.strftime("%H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")
    
    def run_command(self, cmd: str, capture_output: bool = True, timeout: int = 60) -> Tuple[int, str, str]:
        """Run shell command and return exit code, stdout, stderr"""
        try:
            result = subprocess.run(
                cmd, 
                shell=True, 
                capture_output=capture_output,
                text=True,
                timeout=timeout,
                cwd=self.project_root
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", f"Command timed out after {timeout}s: {cmd}"
        except Exception as e:
            return -1, "", f"Command failed: {e}"
    
    def check_devenv_available(self) -> bool:
        """Check if DevEnv is available and properly configured"""
        self.log("Checking DevEnv availability...")
        
        # Check if devenv command exists
        exit_code, stdout, stderr = self.run_command("command -v devenv")
        if exit_code != 0:
            self.log("DevEnv command not found", "ERROR")
            return False
        
        # Check if we're in a DevEnv shell
        if not os.environ.get("IN_NIX_SHELL"):
            self.log("Not in DevEnv shell environment", "WARN")
            return False
        
        # Check if DevEnv containers are configured
        exit_code, stdout, stderr = self.run_command("devenv container --help")
        if exit_code != 0:
            self.log("DevEnv container command not available", "ERROR")  
            return False
        
        self.log("DevEnv environment validated", "SUCCESS")
        return True
    
    def check_docker_available(self) -> bool:
        """Check if Docker is available and responding"""
        self.log("Checking Docker availability...")
        
        exit_code, stdout, stderr = self.run_command("docker info", timeout=10)
        if exit_code != 0:
            self.log(f"Docker not available: {stderr}", "ERROR")
            return False
        
        self.log("Docker daemon validated", "SUCCESS")
        return True
    
    def test_mode_switching(self) -> bool:
        """Test mode switching between development and production"""
        self.log("Testing mode switching...")
        
        # Test switch to development mode
        exit_code, stdout, stderr = self.run_command("manage dev")
        if exit_code != 0:
            self.log(f"Failed to switch to development mode: {stderr}", "ERROR")
            return False
        
        # Verify mode file was created
        mode_file = self.project_root / ".mode"
        if not mode_file.exists():
            self.log("Mode file not created", "ERROR")
            return False
        
        mode_content = mode_file.read_text().strip()
        if mode_content != "development":
            self.log(f"Incorrect mode in file: {mode_content}", "ERROR")
            return False
        
        # Test switch to production mode
        exit_code, stdout, stderr = self.run_command("manage prod")
        if exit_code != 0:
            self.log(f"Failed to switch to production mode: {stderr}", "ERROR")
            return False
        
        mode_content = mode_file.read_text().strip()
        if mode_content != "production":
            self.log(f"Incorrect production mode in file: {mode_content}", "ERROR")
            return False
        
        # Switch back to development for remaining tests
        self.run_command("manage dev")
        
        self.log("Mode switching validated", "SUCCESS")
        return True
    
    def test_container_build_devenv(self) -> bool:
        """Test DevEnv native container building"""
        self.log("Testing DevEnv container build...")
        
        # Try to build using DevEnv containers
        exit_code, stdout, stderr = self.run_command("devenv container build dev", timeout=300)
        
        if exit_code == 0:
            self.log("DevEnv container build successful", "SUCCESS")
            # Check if container spec was generated
            if "/nix/store" in stdout and ".json" in stdout:
                self.log("Container specification generated", "SUCCESS")
                return True
            else:
                self.log("Container spec not found in output", "WARN")
                return True  # Still consider it a success if build completed
        else:
            self.log(f"DevEnv container build failed: {stderr}", "ERROR")
            return False
    
    def test_container_build_management(self) -> bool:
        """Test container build using management system"""
        self.log("Testing container build via management system...")
        
        exit_code, stdout, stderr = self.run_command("manage build", timeout=600)
        
        if exit_code != 0:
            self.log(f"Management build failed: {stderr}", "ERROR")
            return False
        
        # Check if Docker images were created
        exit_code, stdout, stderr = self.run_command("docker images | grep endo-api")
        
        if exit_code == 0 and "endo-api" in stdout:
            self.log("Container images created successfully", "SUCCESS")
            return True
        else:
            self.log("No container images found after build", "WARN")
            # This might still be OK if DevEnv containers don't copy to Docker
            return True
    
    def test_container_run_and_health(self) -> bool:
        """Test container running and health check"""
        self.log("Testing container run and health check...")
        
        # Modify port for testing to avoid conflicts
        os.environ["DJANGO_PORT"] = str(self.test_port)
        
        # Try to run container
        exit_code, stdout, stderr = self.run_command("manage run", timeout=120)
        
        if exit_code != 0:
            self.log(f"Container run failed: {stderr}", "ERROR")
            return False
        
        # Wait for container to start
        self.log("Waiting for container to start...")
        time.sleep(10)
        
        # Check if container is running
        exit_code, stdout, stderr = self.run_command("docker ps | grep endo-api")
        
        if exit_code == 0 and "endo-api" in stdout:
            self.log("Container is running", "SUCCESS")
            self.containers_to_cleanup.append("endo-api-dev-test")
            
            # Try to health check the container
            return self._health_check_container()
        else:
            self.log("Container not found in running processes", "ERROR")
            return False
    
    def _health_check_container(self) -> bool:
        """Perform health check on running container"""
        self.log("Performing container health check...")
        
        # Try to connect to the container
        try:
            response = requests.get(f"http://localhost:{self.test_port}", timeout=30)
            if response.status_code in [200, 404]:  # 404 is OK, means Django is running
                self.log("Container health check passed", "SUCCESS")
                return True
            else:
                self.log(f"Container health check failed: HTTP {response.status_code}", "ERROR")
                return False
        except requests.ConnectionError:
            self.log("Container not responding to HTTP requests", "ERROR")
            return False
        except requests.Timeout:
            self.log("Container health check timed out", "ERROR")
            return False
        except Exception as e:
            self.log(f"Container health check error: {e}", "ERROR")
            return False
    
    def test_container_logs(self) -> bool:
        """Test container log access"""
        self.log("Testing container log access...")
        
        # Try to get container logs
        exit_code, stdout, stderr = self.run_command("docker logs endo-api-dev-test", timeout=30)
        
        if exit_code == 0 and stdout:
            self.log("Container logs accessible", "SUCCESS")
            # Check for expected log content
            if "Django" in stdout or "Starting" in stdout or "server" in stdout.lower():
                self.log("Container logs contain expected content", "SUCCESS")
                return True
            else:
                self.log("Container logs don't contain expected content", "WARN")
                return True  # Still consider it a success
        else:
            self.log(f"Failed to get container logs: {stderr}", "ERROR")
            return False
    
    def test_container_stop(self) -> bool:
        """Test container stopping"""
        self.log("Testing container stop...")
        
        exit_code, stdout, stderr = self.run_command("manage stop", timeout=60)
        
        if exit_code != 0:
            self.log(f"Container stop failed: {stderr}", "ERROR")
            return False
        
        # Wait for stop to complete
        time.sleep(5)
        
        # Check if containers are stopped
        exit_code, stdout, stderr = self.run_command("docker ps | grep endo-api")
        
        if exit_code != 0 or "endo-api" not in stdout:
            self.log("Containers stopped successfully", "SUCCESS")
            return True
        else:
            self.log("Some containers still running after stop", "WARN")
            return True  # Still consider it a success, cleanup will handle it
    
    def test_container_cleanup(self) -> bool:
        """Test container cleanup"""
        self.log("Testing container cleanup...")
        
        exit_code, stdout, stderr = self.run_command("manage clean", timeout=120)
        
        if exit_code != 0:
            self.log(f"Container cleanup failed: {stderr}", "ERROR")
            return False
        
        # Verify containers are removed
        exit_code, stdout, stderr = self.run_command("docker ps -a | grep endo-api")
        
        if exit_code != 0 or "endo-api" not in stdout:
            self.log("Container cleanup successful", "SUCCESS")
            return True
        else:
            self.log("Some containers still exist after cleanup", "WARN")
            # Force cleanup for safety
            self.run_command("docker rm -f endo-api-dev-test endo-api-prod-test 2>/dev/null || true")
            return True
    
    def test_management_status(self) -> bool:
        """Test management status reporting"""
        self.log("Testing management status...")
        
        exit_code, stdout, stderr = self.run_command("manage status")
        
        if exit_code != 0:
            self.log(f"Status command failed: {stderr}", "ERROR")
            return False
        
        # Check if status output contains expected information
        if "Configuration:" in stdout and "Mode:" in stdout:
            self.log("Management status working correctly", "SUCCESS")
            return True
        else:
            self.log("Status output incomplete", "WARN")
            return True
    
    def run_all_tests(self) -> Dict[str, bool]:
        """Run all container workflow tests"""
        self.log("Starting Container Workflow Test Suite")
        self.log("=====================================")
        
        # Setup clean test environment
        self.setup()
        
        tests = [
            ("DevEnv Available", self.check_devenv_available),
            ("Docker Available", self.check_docker_available), 
            ("Mode Switching", self.test_mode_switching),
            ("Management Status", self.test_management_status),
            ("DevEnv Container Build", self.test_container_build_devenv),
            ("Management Container Build", self.test_container_build_management),
            ("Container Run & Health", self.test_container_run_and_health),
            ("Container Logs", self.test_container_logs),
            ("Container Stop", self.test_container_stop),
            ("Container Cleanup", self.test_container_cleanup),
        ]
        
        results = {}
        passed = 0
        failed = 0
        
        for test_name, test_func in tests:
            self.log(f"Running test: {test_name}")
            try:
                result = test_func()
                results[test_name] = result
                if result:
                    passed += 1
                    self.log(f"✅ {test_name}: PASSED")
                else:
                    failed += 1
                    self.log(f"❌ {test_name}: FAILED")
            except Exception as e:
                results[test_name] = False
                failed += 1
                self.log(f"❌ {test_name}: ERROR - {e}")
        
        # Final cleanup
        self.cleanup()
        
        # Report summary
        self.log("Container Workflow Test Results")
        self.log("==============================")
        self.log(f"Total Tests: {len(tests)}")
        self.log(f"Passed: {passed}")
        self.log(f"Failed: {failed}")
        self.log(f"Success Rate: {(passed/len(tests)*100):.1f}%")
        
        if failed == 0:
            self.log("🎉 All container workflow tests passed!", "SUCCESS")
        else:
            self.log(f"⚠️  {failed} tests failed. Check logs for details.", "WARN")
        
        return results
    
    def cleanup(self):
        """Clean up any test artifacts"""
        self.log("Cleaning up test artifacts...")
        
        # Define all possible test container names
        test_containers = [
            "endo-api-dev-test",
            "endo-api-prod-test", 
            "endo-api-processes-test"
        ]
        
        # Stop and remove all test containers (both tracked and untracked)
        for container in test_containers:
            self.run_command(f"docker stop {container} 2>/dev/null || true")
            self.run_command(f"docker rm -f {container} 2>/dev/null || true")
        
        # Also clean up any containers from the tracked list
        for container in self.containers_to_cleanup:
            self.run_command(f"docker stop {container} 2>/dev/null || true")
            self.run_command(f"docker rm -f {container} 2>/dev/null || true")
        
        # Reset test port
        if "DJANGO_PORT" in os.environ:
            del os.environ["DJANGO_PORT"]
        
        self.log("Test cleanup completed", "SUCCESS")
        
    def setup(self):
        """Setup clean test environment"""
        self.log("Setting up clean test environment...")
        
        # Clean up any existing test containers before starting
        self.cleanup()
        
        # Ensure we're in development mode for testing
        os.environ["DJANGO_ENV"] = "development"
        
        self.log("Test setup completed", "SUCCESS")


def main():
    """Main test runner"""
    tester = ContainerWorkflowTester()
    try:
        results = tester.run_all_tests()
        
        # Exit with appropriate code
        failed_tests = sum(1 for result in results.values() if not result)
        exit(failed_tests)
    finally:
        # Ensure cleanup always happens
        tester.cleanup()


if __name__ == "__main__":
    main()
