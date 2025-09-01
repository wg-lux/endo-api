#!/usr/bin/env bash
# Container workflow testing wrapper
# Integrates with the existing test framework

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Test container workflow using Python test suite
run_container_workflow_tests() {
    log_info "Running Container Workflow Tests..."
    
    cd "$PROJECT_ROOT"
    
    # Check if required Python packages are available
    if ! python -c "import requests" 2>/dev/null; then
        log_warning "Installing required test dependencies..."
        uv add requests --dev 2>/dev/null || pip install requests 2>/dev/null || {
            log_error "Could not install requests package"
            return 1
        }
    fi
    
    # Run the Python test suite
    if python tests/test_container_workflow.py; then
        log_success "Container workflow tests completed successfully"
        return 0
    else
        log_error "Container workflow tests failed"
        return 1
    fi
}

# Quick container smoke test
run_container_smoke_test() {
    log_info "Running Container Smoke Test..."
    
    cd "$PROJECT_ROOT"
    
    # Test basic management commands
    log_info "Testing basic management commands..."
    
    # Test status command
    if ! manage status >/dev/null 2>&1; then
        log_error "Management status command failed"
        return 1
    fi
    
    # Test mode switching
    log_info "Testing mode switching..."
    if ! manage dev >/dev/null 2>&1; then
        log_error "Mode switching to dev failed"
        return 1
    fi
    
    log_success "Container smoke test passed"
    return 0
}

# Test DevEnv container build (quick)
test_devenv_container_build() {
    log_info "Testing DevEnv container build..."
    
    cd "$PROJECT_ROOT"
    
    # Try to build a DevEnv container
    log_info "Attempting DevEnv container build..."
    
    # Use timeout to prevent hanging
    if timeout 300 devenv container build dev >/dev/null 2>&1; then
        log_success "DevEnv container build successful"
        return 0
    else
        log_warning "DevEnv container build failed or timed out"
        return 1
    fi
}

# Test Docker integration
test_docker_integration() {
    log_info "Testing Docker integration..."
    
    # Check Docker availability
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker not available, skipping Docker integration tests"
        return 0
    fi
    
    # Check if any endo-api images exist
    if docker images | grep -q endo-api; then
        log_success "Endo-API Docker images found"
    else
        log_warning "No Endo-API Docker images found"
    fi
    
    # Check if any endo-api containers are running
    if docker ps | grep -q endo-api; then
        log_info "Endo-API containers currently running:"
        docker ps --filter "name=endo-api" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        log_info "No Endo-API containers currently running"
    fi
    
    return 0
}

# Cleanup test containers
cleanup_test_containers() {
    log_info "Cleaning up test containers..."
    
    # Use the management task to clean up test containers
    if command -v devenv >/dev/null 2>&1; then
        devenv tasks run container:cleanup-tests >/dev/null 2>&1 || true
    fi
    
    # Fallback manual cleanup
    for container in endo-api-dev-test endo-api-prod-test endo-api-processes-test; do
        if docker ps -q -f name="$container" 2>/dev/null | grep -q .; then
            docker stop "$container" >/dev/null 2>&1 || true
        fi
        if docker ps -aq -f name="$container" 2>/dev/null | grep -q .; then
            docker rm -f "$container" >/dev/null 2>&1 || true
        fi
    done
    
    log_info "Test container cleanup completed"
}

# Main test runner
main() {
    echo "Container Workflow Testing"
    echo "=========================="
    
    # Set up cleanup trap
    trap cleanup_test_containers EXIT
    
    case "${1:-full}" in
        "smoke")
            cleanup_test_containers  # Clean before testing
            run_container_smoke_test
            ;;
        "build") 
            cleanup_test_containers  # Clean before testing
            test_devenv_container_build
            ;;
        "docker")
            cleanup_test_containers  # Clean before testing
            test_docker_integration
            ;;
        "full"|"all")
            cleanup_test_containers  # Clean before testing
            run_container_workflow_tests
            ;;
        *)
            echo "Usage: $0 [smoke|build|docker|full]"
            echo ""
            echo "Test modes:"
            echo "  smoke  - Quick smoke test of basic functionality"
            echo "  build  - Test DevEnv container building"
            echo "  docker - Test Docker integration"  
            echo "  full   - Run comprehensive container workflow tests"
            exit 1
            ;;
    esac
}

main "$@"
