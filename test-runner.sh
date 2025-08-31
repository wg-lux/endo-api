#!/usr/bin/env bash

# Comprehensive Test Runner for Endo API
# ======================================
# 
# This script provides an easy interface to run the comprehensive devenv test suite
# with proper error handling, logging, and reporting.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILED_TESTS=()

# Function to run a single test
run_test() {
    local test_name="$1"
    local test_description="$2"
    
    echo ""
    log_info "Running test: $test_description"
    echo "----------------------------------------"
    
    if devenv test "$test_name"; then
        log_success "PASSED: $test_description"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "FAILED: $test_description"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to run a test with skip capability
run_test_with_skip() {
    local test_name="$1"
    local test_description="$2"
    local skip_condition="$3"
    
    if eval "$skip_condition"; then
        log_warning "SKIPPED: $test_description (condition: $skip_condition)"
        ((TESTS_SKIPPED++))
        return 0
    else
        run_test "$test_name" "$test_description"
    fi
}

# Function to show test summary
show_summary() {
    echo ""
    echo "========================================"
    echo "           TEST SUMMARY"
    echo "========================================"
    
    log_success "Tests Passed: $TESTS_PASSED"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Tests Failed: $TESTS_FAILED"
        echo ""
        log_error "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi
    
    if [ $TESTS_SKIPPED -gt 0 ]; then
        log_warning "Tests Skipped: $TESTS_SKIPPED"
    fi
    
    echo ""
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo "Total Tests: $total"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 ALL TESTS PASSED!"
        return 0
    else
        log_error "💥 SOME TESTS FAILED!"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if we're in devenv
    if [ -z "${DEVENV_ROOT:-}" ]; then
        log_error "Not in devenv environment. Run: devenv shell"
        exit 1
    fi
    
    # Check if manage command exists
    if ! command -v manage >/dev/null 2>&1; then
        log_error "manage command not found. Ensure devenv is properly setup."
        exit 1
    fi
    
    # Check if required files exist
    local required_files=("devenv.nix" "app_config.nix" "devenv/management.nix")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Function to prepare test environment
prepare_environment() {
    log_info "Preparing test environment..."
    
    # Ensure clean state
    rm -f .mode 2>/dev/null || true
    
    # Ensure required directories exist
    mkdir -p data conf staticfiles
    
    log_success "Test environment prepared"
}

# Main function
main() {
    local test_suite="${1:-quick}"
    
    echo "🧪 Endo API Comprehensive Test Suite"
    echo "====================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Prepare environment
    prepare_environment
    
    case "$test_suite" in
        "quick"|"q")
            echo "Running Quick Test Suite..."
            run_test "environment-setup" "Environment Setup"
            run_test "unified-management-system" "Unified Management System"
            run_test "configuration-system" "Configuration System"
            ;;
            
        "workflows"|"w")
            echo "Running Workflow Test Suite..."
            run_test "development-workflow" "Development Workflow"
            run_test "production-workflow" "Production Workflow" 
            run_test "database-operations" "Database Operations"
            ;;
            
        "containers"|"c")
            echo "Running Container Test Suite..."
            run_test_with_skip "container-build" "Container Build" "! command -v docker >/dev/null 2>&1"
            run_test_with_skip "container-runtime" "Container Runtime" "! command -v docker >/dev/null 2>&1"
            ;;
            
        "e2e"|"end-to-end")
            echo "Running End-to-End Test Suite..."
            run_test "end-to-end-development" "End-to-End Development Workflow"
            run_test "end-to-end-production" "End-to-End Production Workflow"
            ;;
            
        "full"|"all"|"f")
            echo "Running Complete Test Suite..."
            echo "This may take several minutes..."
            
            # Core tests
            run_test "environment-setup" "Environment Setup"
            run_test "unified-management-system" "Unified Management System"
            run_test "configuration-system" "Configuration System"
            
            # Workflow tests
            run_test "development-workflow" "Development Workflow"
            run_test "production-workflow" "Production Workflow"
            run_test "database-operations" "Database Operations"
            
            # Container tests (with skip capability)
            run_test_with_skip "container-build" "Container Build" "! command -v docker >/dev/null 2>&1"
            run_test_with_skip "container-runtime" "Container Runtime" "! command -v docker >/dev/null 2>&1"
            
            # End-to-end tests
            run_test "end-to-end-development" "End-to-End Development Workflow"
            run_test "end-to-end-production" "End-to-End Production Workflow"
            
            # Additional tests
            run_test "backwards-compatibility" "Backwards Compatibility"
            run_test "gpu-support" "GPU Support"
            ;;
            
        "ci")
            echo "Running CI/CD Compatible Test Suite..."
            
            # Essential tests only (no container/GPU tests that may fail in CI)
            run_test "environment-setup" "Environment Setup"
            run_test "unified-management-system" "Unified Management System"
            run_test "configuration-system" "Configuration System"
            run_test "development-workflow" "Development Workflow"
            run_test "database-operations" "Database Operations"
            
            # Only run container tests if Docker is available and working
            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                log_info "Docker available in CI, running container tests..."
                run_test "container-build" "Container Build"
                run_test "container-runtime" "Container Runtime"
            else
                log_warning "Docker unavailable in CI, skipping container tests"
                ((TESTS_SKIPPED += 2))
            fi
            ;;
            
        "help"|"-h"|"--help")
            echo "Usage: $0 [test-suite]"
            echo ""
            echo "Available test suites:"
            echo "  quick      - Quick core functionality tests (default)"
            echo "  workflows  - Development/production workflow tests"
            echo "  containers - Container build and runtime tests"
            echo "  e2e        - End-to-end workflow tests"
            echo "  full       - Complete test suite"
            echo "  ci         - CI/CD compatible tests"
            echo "  help       - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0              # Run quick tests"
            echo "  $0 full         # Run complete test suite"
            echo "  $0 containers   # Test only container functionality"
            exit 0
            ;;
            
        *)
            log_error "Unknown test suite: $test_suite"
            echo "Use '$0 help' to see available options."
            exit 1
            ;;
    esac
    
    # Show summary and exit with appropriate code
    show_summary
}

# Run main function with all arguments
main "$@"
