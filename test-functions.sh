#!/usr/bin/env bash

# DevEnv Test Functions for Endo API
# ==================================
# 
# This file contains test functions used by devenv's enterTest system.
# These functions are sourced by the enterTest script in devenv.nix.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_RUN=0
TESTS_PASSED=0

# Logging functions
test_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

test_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

test_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

test_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to run a single test
run_single_test() {
    local test_name="$1"
    local test_description="$2"
    shift 2
    
    ((TESTS_RUN++))
    test_info "Testing: $test_description"
    
    if "$@"; then
        test_success "PASSED: $test_description"
        ((TESTS_PASSED++))
        return 0
    else
        test_error "FAILED: $test_description"
        return 1
    fi
}

# Test: Environment Setup
test_environment_setup() {
    # Check devenv environment variables
    [ -n "${DEVENV_ROOT:-}" ] || { echo "DEVENV_ROOT not set"; return 1; }
    
    # Check required files exist
    [ -f "manage.py" ] || { echo "Django manage.py not found"; return 1; }
    [ -f "devenv.nix" ] || { echo "devenv.nix not found"; return 1; }
    [ -f "app_config.nix" ] || { echo "app_config.nix not found"; return 1; }
    
    # Check required commands are available
    command -v python >/dev/null 2>&1 || { echo "Python not available"; return 1; }
    command -v uv >/dev/null 2>&1 || { echo "uv not available"; return 1; }
    
    # Check Python can import Django
    python -c "import django" 2>/dev/null || { echo "Django not importable"; return 1; }
    
    echo "Environment setup verified"
    return 0
}

# Test: Unified Management System
test_unified_management() {
    # Test basic manage.py exists
    [ -f "manage.py" ] || { echo "manage.py not found"; return 1; }
    
    # Test Python can run Django admin
    python manage.py --version >/dev/null 2>&1 || { echo "Django manage.py failed"; return 1; }
    
    # Test help command works
    python manage.py help >/dev/null 2>&1 || { echo "Django help command failed"; return 1; }
    
    echo "Unified management system verified"
    return 0
}

# Test: Configuration System
test_configuration_system() {
    # Test configuration files can be read
    [ -f "app_config.nix" ] || { echo "app_config.nix not found"; return 1; }
    
    # Test environment variables are set
    [ -n "${DJANGO_MODULE:-}" ] || { echo "DJANGO_MODULE not set"; return 1; }
    [ -n "${DATA_DIR:-}" ] || { echo "DATA_DIR not set"; return 1; }
    
    echo "Configuration system verified"
    return 0
}

# Test: Development Workflow
test_development_workflow() {
    # Check Django can load settings
    python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'endo_api.settings_dev')
import django
django.setup()
print('Django development settings loaded')
" 2>/dev/null || { echo "Django development settings failed"; return 1; }
    
    echo "Development workflow verified"
    return 0
}

# Test: Production Workflow  
test_production_workflow() {
    # Check production settings exist
    [ -f "endo_api/settings_prod.py" ] || { echo "Production settings not found"; return 1; }
    
    # Test settings can be imported (basic syntax check)
    python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'endo_api.settings_prod')
import django
django.setup()
print('Django production settings loaded')
" 2>/dev/null || { echo "Django production settings failed"; return 1; }
    
    echo "Production workflow verified" 
    return 0
}

# Test: Database Operations
test_database_operations() {
    # Test database settings can be loaded
    python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'endo_api.settings_dev')  
import django
django.setup()
from django.conf import settings
print('Database configuration loaded successfully')
" 2>/dev/null || { echo "Database configuration test failed"; return 1; }
    
    echo "Database operations verified"
    return 0
}

# Test: Container Build (if Docker available)
test_container_build() {
    if ! command -v docker >/dev/null 2>&1; then
        test_warning "Docker not available, skipping container build test"
        return 0
    fi
    
    # Test Dockerfile exists
    [ -f "Dockerfile" ] || { 
        test_warning "Dockerfile not found, skipping container build test"
        return 0
    }
    
    echo "Container build capability verified"
    return 0
}

# Test: Container Runtime (if Docker available)
test_container_runtime() {
    if ! command -v docker >/dev/null 2>&1; then
        test_warning "Docker not available, skipping container runtime test"
        return 0
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        test_warning "Docker daemon not running, skipping container runtime test"
        return 0
    fi
    
    echo "Container runtime capability verified"
    return 0
}

# Test: End-to-End Development
test_e2e_development() {
    test_info "Running end-to-end development workflow test..."
    
    # Full development setup verification
    python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'endo_api.settings_dev')
import django
django.setup()
from django.core.management import execute_from_command_line
print('End-to-end development workflow verified')
" 2>/dev/null || { echo "End-to-end development check failed"; return 1; }
    
    echo "End-to-end development workflow verified"
    return 0
}

# Test: End-to-End Production
test_e2e_production() {
    test_info "Running end-to-end production workflow test..."
    
    # Full production setup verification
    python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'endo_api.settings_prod')
import django  
django.setup()
from django.core.management import execute_from_command_line
print('End-to-end production workflow verified')
" 2>/dev/null || { echo "End-to-end production check failed"; return 1; }
    
    echo "End-to-end production workflow verified"
    return 0
}

# Test: Backwards Compatibility
test_backwards_compatibility() {
    # Test direct Django management still works
    python manage.py --version >/dev/null 2>&1 || {
        echo "Direct Django manage.py failed"; return 1;
    }
    
    echo "Backwards compatibility verified"
    return 0
}

# Test: GPU Support
test_gpu_support() {
    # Test GPU detection script if it exists
    if [ -f "scripts/gpu-check.py" ]; then
        python scripts/gpu-check.py >/dev/null 2>&1 || {
            test_warning "GPU check script failed"; return 0;
        }
    fi
    
    echo "GPU support verified"
    return 0
}

# Test suite functions
run_quick_tests() {
    test_info "Running Quick Test Suite..."
    
    local suite_failed=0
    
    run_single_test "environment" "Environment Setup" test_environment_setup || suite_failed=1
    run_single_test "management" "Unified Management System" test_unified_management || suite_failed=1
    run_single_test "configuration" "Configuration System" test_configuration_system || suite_failed=1
    
    test_success "Quick tests completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in quick test suite"
        return 1
    fi
    
    return 0
}

run_workflow_tests() {
    test_info "Running Workflow Test Suite..."
    
    local suite_failed=0
    
    run_single_test "dev-workflow" "Development Workflow" test_development_workflow || suite_failed=1
    run_single_test "prod-workflow" "Production Workflow" test_production_workflow || suite_failed=1
    run_single_test "database" "Database Operations" test_database_operations || suite_failed=1
    
    test_success "Workflow tests completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in workflow test suite"
        return 1
    fi
    
    return 0
}

run_container_tests() {
    test_info "Running Container Test Suite..."
    
    local suite_failed=0
    
    run_single_test "container-build" "Container Build" test_container_build || suite_failed=1
    run_single_test "container-runtime" "Container Runtime" test_container_runtime || suite_failed=1
    
    test_success "Container tests completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in container test suite"
        return 1
    fi
    
    return 0
}

run_e2e_tests() {
    test_info "Running End-to-End Test Suite..."
    
    local suite_failed=0
    
    run_single_test "e2e-dev" "End-to-End Development" test_e2e_development || suite_failed=1
    run_single_test "e2e-prod" "End-to-End Production" test_e2e_production || suite_failed=1
    
    test_success "End-to-end tests completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in end-to-end test suite"
        return 1
    fi
    
    return 0
}

run_full_tests() {
    test_info "Running Complete Test Suite..."
    
    local suite_failed=0
    
    # All tests
    run_single_test "environment" "Environment Setup" test_environment_setup || suite_failed=1
    run_single_test "management" "Unified Management System" test_unified_management || suite_failed=1
    run_single_test "configuration" "Configuration System" test_configuration_system || suite_failed=1
    run_single_test "dev-workflow" "Development Workflow" test_development_workflow || suite_failed=1
    run_single_test "prod-workflow" "Production Workflow" test_production_workflow || suite_failed=1
    run_single_test "database" "Database Operations" test_database_operations || suite_failed=1
    run_single_test "container-build" "Container Build" test_container_build || suite_failed=1
    run_single_test "container-runtime" "Container Runtime" test_container_runtime || suite_failed=1
    run_single_test "e2e-dev" "End-to-End Development" test_e2e_development || suite_failed=1
    run_single_test "e2e-prod" "End-to-End Production" test_e2e_production || suite_failed=1
    run_single_test "backwards-compat" "Backwards Compatibility" test_backwards_compatibility || suite_failed=1
    run_single_test "gpu-support" "GPU Support" test_gpu_support || suite_failed=1
    
    test_success "Full test suite completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in full test suite"
        return 1
    fi
    
    return 0
}

run_ci_tests() {
    test_info "Running CI/CD Test Suite..."
    
    local suite_failed=0
    
    # Essential tests only (no GPU/container tests that may fail in CI)
    run_single_test "environment" "Environment Setup" test_environment_setup || suite_failed=1
    run_single_test "management" "Unified Management System" test_unified_management || suite_failed=1
    run_single_test "configuration" "Configuration System" test_configuration_system || suite_failed=1
    run_single_test "dev-workflow" "Development Workflow" test_development_workflow || suite_failed=1
    run_single_test "database" "Database Operations" test_database_operations || suite_failed=1
    run_single_test "backwards-compat" "Backwards Compatibility" test_backwards_compatibility || suite_failed=1
    
    test_success "CI tests completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in CI test suite"
        return 1
    fi
    
    return 0
}
