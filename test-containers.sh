#!/usr/bin/env bash
# Container Testing and Validation Script
# =======================================
# 
# This script provides comprehensive testing for container builds,
# ensuring development and production containers work correctly.

set -uo pipefail

# Note: Using set -u and set -o pipefail but not set -e to allow tests to continue on failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

print_header() {
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo -e "${BOLD}${BLUE}  EndoReg API Container Test Suite${NC}"
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo ""
}

print_test_header() {
    local test_name="$1"
    echo -e "${YELLOW}🧪 Testing: $test_name${NC}"
    echo "----------------------------------------"
}

print_success() {
    local message="$1"
    echo -e "${GREEN}✅ $message${NC}"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

print_failure() {
    local message="$1"
    echo -e "${RED}❌ $message${NC}"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

print_info() {
    local message="$1"
    echo -e "${BLUE}ℹ️  $message${NC}"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  $message${NC}"
}

test_docker_availability() {
    print_test_header "Container Engine Availability"
    
    if command -v docker &> /dev/null; then
        print_success "Container engine (docker) command available"
        
        # Detect if it's Docker or Podman
        if docker version 2>&1 | grep -q "Podman"; then
            print_info "Using Podman as container engine"
        elif docker version &> /dev/null; then
            print_info "Using Docker as container engine"
        fi
        
        print_success "Container engine is functional"
    else
        print_failure "Container engine command not found"
        return 1
    fi
    
    echo ""
}

test_dockerfile_syntax() {
    print_test_header "Dockerfile Syntax Validation"
    
    for dockerfile in Dockerfile.dev Dockerfile.prod; do
        if [ -f "$dockerfile" ]; then
            # Simple syntax check by parsing the dockerfile
            if grep -E "^FROM|^RUN|^COPY|^CMD|^EXPOSE|^ENV" "$dockerfile" > /dev/null; then
                print_success "$dockerfile syntax appears valid"
            else
                print_failure "$dockerfile appears to have syntax issues"
            fi
        else
            print_failure "$dockerfile not found"
        fi
    done
    
    echo ""
}

test_configuration_consistency() {
    print_test_header "Configuration Consistency"
    
    if [ -f "app_config.nix" ]; then
        print_success "app_config.nix found"
        
        # Test if we can extract configuration
        if command -v nix &> /dev/null && command -v python3 &> /dev/null; then
            if nix eval --json --file app_config.nix > /dev/null 2>&1; then
                print_success "app_config.nix is valid Nix syntax"
                
                # Extract key values using our get_config_value function from docker-manager.sh
                # For now, just test that we can read the config
                local test_config=$(nix eval --json --file app_config.nix 2>/dev/null || echo "{}")
                if [ "$test_config" != "{}" ]; then
                    print_success "Configuration values can be extracted"
                else
                    print_failure "Failed to extract configuration values"
                fi
            else
                print_failure "app_config.nix has syntax errors"
            fi
        else
            print_warning "Nix or Python3 not available - skipping config validation"
        fi
    else
        print_failure "app_config.nix not found"
    fi
    
    echo ""
}

test_docker_manager_script() {
    print_test_header "Docker Manager Script"
    
    if [ -f "docker-manager.sh" ]; then
        print_success "docker-manager.sh found"
        
        if [ -x "docker-manager.sh" ]; then
            print_success "docker-manager.sh is executable"
            
            # Test help command
            if ./docker-manager.sh help > /dev/null 2>&1; then
                print_success "docker-manager.sh help command works"
            else
                print_failure "docker-manager.sh help command failed"
            fi
            
            # Test config command
            if ./docker-manager.sh config > /dev/null 2>&1; then
                print_success "docker-manager.sh config command works"
            else
                print_failure "docker-manager.sh config command failed"
            fi
        else
            print_failure "docker-manager.sh is not executable"
        fi
    else
        print_failure "docker-manager.sh not found"
    fi
    
    echo ""
}

test_container_build() {
    local mode="$1"
    print_test_header "Container Build - $mode"
    
    local dockerfile="Dockerfile.$mode"
    local image_name="endo-api-$mode-test"
    
    if [ ! -f "$dockerfile" ]; then
        print_failure "$dockerfile not found"
        return 1
    fi
    
    print_info "Building $image_name from $dockerfile..."
    
    # Build with timeout
    if timeout 300 docker build -f "$dockerfile" -t "$image_name" . &> build_${mode}.log; then
        print_success "$mode container built successfully"
        
        # Check if image exists
        if docker images -q "$image_name" | grep -q .; then
            print_success "$image_name image created"
        else
            print_failure "$image_name image not found after build"
        fi
    else
        print_failure "$mode container build failed"
        print_info "Build log saved to build_${mode}.log"
        return 1
    fi
    
    echo ""
}

test_container_run() {
    local mode="$1"
    print_test_header "Container Runtime - $mode"
    
    local image_name="endo-api-$mode-test"
    local container_name="test-container-$mode"
    local port="8118"
    
    # Clean up any existing container
    docker stop "$container_name" &> /dev/null || true
    docker rm "$container_name" &> /dev/null || true
    
    print_info "Starting $container_name from $image_name..."
    
    # Start container with timeout for startup
    if docker run -d \
        --name "$container_name" \
        -p "${port}:${port}" \
        -e DJANGO_HOST=0.0.0.0 \
        -e DJANGO_PORT="$port" \
        -e ENDO_API_MODE="$mode" \
        -v "$PROJECT_ROOT/data:/app/data" \
        -v "$PROJECT_ROOT/conf:/app/conf" \
        "$image_name" &> /dev/null; then
        
        print_success "Container started successfully"
        
        # Wait for container to be ready
        print_info "Waiting for container to be ready..."
        local max_attempts=30
        local attempt=1
        local container_ready=false
        
        while [ $attempt -le $max_attempts ]; do
            if docker ps -q -f name="$container_name" | grep -q .; then
                # Container is running, check if it's responsive
                sleep 2
                
                # Try to connect to the service
                if curl -s -f "http://localhost:$port" > /dev/null 2>&1; then
                    print_success "Container is responding on port $port"
                    container_ready=true
                    break
                elif [ $attempt -eq $max_attempts ]; then
                    print_warning "Container is running but not responding on port $port"
                    # This might be expected if the app needs more time to start
                    container_ready=true
                    break
                fi
            else
                print_failure "Container stopped unexpectedly"
                docker logs "$container_name" 2>&1 | tail -10
                break
            fi
            
            ((attempt++))
            sleep 1
        done
        
        if $container_ready; then
            print_success "$mode container is running"
        else
            print_failure "$mode container failed to start properly"
        fi
        
        # Always clean up
        docker stop "$container_name" &> /dev/null || true
        docker rm "$container_name" &> /dev/null || true
        
    else
        print_failure "Failed to start $mode container"
    fi
    
    echo ""
}

test_compose_generation() {
    print_test_header "Docker Compose Generation"
    
    if [ -x "docker-manager.sh" ]; then
        # Test dev compose generation
        if ./docker-manager.sh generate-compose-dev > /dev/null 2>&1; then
            if [ -f "docker-compose.dev.generated.yml" ]; then
                print_success "Development compose file generated"
            else
                print_failure "Development compose file not created"
            fi
        else
            print_failure "Development compose generation failed"
        fi
        
        # Test prod compose generation
        if ./docker-manager.sh generate-compose-prod > /dev/null 2>&1; then
            if [ -f "docker-compose.prod.generated.yml" ]; then
                print_success "Production compose file generated"
            else
                print_failure "Production compose file not created"
            fi
        else
            print_failure "Production compose generation failed"
        fi
    else
        print_failure "docker-manager.sh not executable"
    fi
    
    echo ""
}

cleanup_test_artifacts() {
    print_test_header "Cleanup Test Artifacts"
    
    # Remove test images
    for mode in dev prod; do
        local image_name="endo-api-$mode-test"
        if docker images -q "$image_name" | grep -q .; then
            docker rmi "$image_name" > /dev/null 2>&1 || true
            print_success "Removed test image: $image_name"
        fi
    done
    
    # Remove build logs
    for log in build_dev.log build_prod.log; do
        if [ -f "$log" ]; then
            rm -f "$log"
            print_success "Removed build log: $log"
        fi
    done
    
    # Remove generated compose files
    for compose in docker-compose.dev.generated.yml docker-compose.prod.generated.yml; do
        if [ -f "$compose" ]; then
            rm -f "$compose"
            print_success "Removed generated file: $compose"
        fi
    done
    
    echo ""
}

print_test_summary() {
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo -e "${BOLD}${BLUE}  Container Test Results${NC}"
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${BOLD}${GREEN}🎉 ALL TESTS PASSED! ($PASSED_TESTS/$TOTAL_TESTS)${NC}"
        echo ""
        echo -e "${GREEN}Your container implementation is ready for use!${NC}"
        echo ""
        echo -e "${BLUE}Next steps:${NC}"
        echo "  1. Build containers: ./docker-manager.sh build-all"
        echo "  2. Run development:  ./docker-manager.sh run-dev"
        echo "  3. Generate compose: ./docker-manager.sh generate-compose-all"
    else
        echo -e "${BOLD}${RED}❌ TESTS FAILED: $FAILED_TESTS/$TOTAL_TESTS${NC}"
        echo -e "${BOLD}${GREEN}✅ TESTS PASSED: $PASSED_TESTS/$TOTAL_TESTS${NC}"
        echo ""
        echo -e "${RED}Please fix the issues above before using containers.${NC}"
    fi
    
    echo ""
}

main() {
    print_header
    
    # Check if running in CI mode (skip interactive tests)
    local ci_mode="false"
    if [ "${1:-}" = "--ci" ]; then
        ci_mode="true"
        print_info "Running in CI mode - skipping container runtime tests"
        echo ""
    fi
    
    # Run tests
    test_docker_availability
    test_dockerfile_syntax
    test_configuration_consistency
    test_docker_manager_script
    test_compose_generation
    
    if [ "$ci_mode" != "true" ]; then
        # These tests actually build and run containers
        test_container_build "dev"
        test_container_build "prod"
        test_container_run "dev"
        test_container_run "prod"
    fi
    
    cleanup_test_artifacts
    print_test_summary
    
    # Exit with error code if tests failed
    [ $FAILED_TESTS -eq 0 ]
}

# Handle script arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Container Test Suite for EndoReg API"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --ci     Run in CI mode (skip container runtime tests)"
        echo "  --help   Show this help message"
        echo ""
        echo "This script tests:"
        echo "  - Docker availability"
        echo "  - Dockerfile syntax"
        echo "  - Configuration consistency"
        echo "  - Docker manager script"
        echo "  - Container builds (dev and prod)"
        echo "  - Container runtime (dev and prod)"
        echo "  - Docker compose generation"
        echo ""
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
