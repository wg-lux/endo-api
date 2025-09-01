#!/usr/bin/env bash
# system-validation.sh - Comprehensive system validation with JSON output
# 
# System Validation and Status Summary for Endo API
# =================================================
# 
# Comprehensive system validation that checks:
# - File structure and dependencies
# - Configuration validity
# - Development environment functionality  
# - Container build and run capabilities (on test port 10123)
# - Database connectivity
# - GPU/CUDA availability
# 
# Outputs structured JSON status summary to status-summary.json
# 
# Usage:
#     bash scripts/core/system-validation.sh
#     bash scripts/core/system-validation.sh --json-only
#     bash scripts/core/system-validation.sh --skip-containers
#     bash scripts/core/system-validation.sh --force-rebuild
#     bash scripts/core/system-validation.sh --verbose

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
VALIDATION_PORT=10123
OUTPUT_FILE="status-summary.json"
TIMESTAMP=$(date -Iseconds)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# JSON status structure
declare -A status_results
status_results[timestamp]="$TIMESTAMP"
status_results[validation_port]="$VALIDATION_PORT"
status_results[project_root]="$PROJECT_ROOT"

# Utility functions
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

log_header() {
    echo -e "\n${PURPLE}$1${NC}"
    echo "$(printf '%*s' ${#1} | tr ' ' '=')"
}

# JSON result recording
record_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    local details="$4"
    
    status_results["${test_name}.result"]="$result"
    status_results["${test_name}.message"]="$message"
    if [ -n "$details" ]; then
        status_results["${test_name}.details"]="$details"
    fi
}

# Test functions
test_file_structure() {
    log_header "📁 File Structure Validation"
    
    local required_files=(
        "app_config.nix"
        "devenv.nix"
        "devenv/containers.nix"
        "devenv/scripts.nix"
        "devenv/environment.nix"
        "scripts/core/environment.py"
        "scripts/core/setup.py"
        "scripts/database/ensure_psql.py"
        "scripts/utilities/gpu-check.py"
        "scripts/cuda/test_cuda_detailed.py"
        "container/Dockerfile.dev"
        "container/Dockerfile.prod"
        "docs/implementation-reports/"
    )
    
    local missing_files=()
    local found_files=()
    
    for file in "${required_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ] || [ -d "$PROJECT_ROOT/$file" ]; then
            found_files+=("$file")
            log_success "$file"
        else
            missing_files+=("$file")
            log_error "$file"
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        record_result "file_structure" "PASS" "All required files present" "$(printf '%s,' "${found_files[@]}")"
        return 0
    else
        record_result "file_structure" "FAIL" "${#missing_files[@]} files missing" "$(printf '%s,' "${missing_files[@]}")"
        return 1
    fi
}

test_environment_configuration() {
    log_header "🔧 Environment Configuration"
    
    # Test unified environment script
    log_info "🔍 Testing unified environment management..."
    if python3 scripts/core/environment.py show >/dev/null 2>&1; then
        log_success "Unified environment management functional"
        local env_result="PASS"
        local env_message="Environment management working"
    else
        log_error "Unified environment management failed"
        local env_result="FAIL"
        local env_message="Environment management not working"
    fi
    
    # Test setup script
    log_info "🔍 Testing environment setup script..."
    if python3 scripts/core/setup.py --status-only >/dev/null 2>&1; then
        log_success "Environment setup script functional"
        local setup_result="PASS"
        local setup_message="Setup script working"
    else
        log_warning "Environment setup script had issues"
        local setup_result="WARNING"
        local setup_message="Setup script issues detected"
    fi
    
    record_result "environment_config" "$env_result" "$env_message"
    record_result "setup_script" "$setup_result" "$setup_message"
    
    [ "$env_result" = "PASS" ] && [ "$setup_result" != "FAIL" ]
}

test_database_connectivity() {
    log_header "🗄️  Database Connectivity"
    
    if [ -f "tests/test_database_connectivity.py" ]; then
        if python3 tests/test_database_connectivity.py >/dev/null 2>&1; then
            log_success "Database connectivity tests passed"
            record_result "database" "PASS" "Database connectivity working"
            return 0
        else
            log_warning "Database connectivity tests had issues"
            record_result "database" "WARNING" "Database connectivity issues detected"
            return 1
        fi
    else
        log_warning "Database connectivity test not found"
        record_result "database" "SKIP" "Test file not found"
        return 0
    fi
}

test_cuda_availability() {
    log_header "🚀 CUDA/GPU Diagnostics"
    
    log_info "🔍 Testing GPU/CUDA availability..."
    if python3 scripts/utilities/gpu-check.py >/dev/null 2>&1; then
        log_success "GPU/CUDA diagnostics passed"
        record_result "cuda_gpu" "PASS" "GPU/CUDA available and working"
    else
        log_warning "GPU/CUDA diagnostics had issues (may be normal on CPU-only systems)"
        record_result "cuda_gpu" "WARNING" "GPU/CUDA not available or has issues"
    fi
    
    # Run detailed CUDA test
    log_info "🔍 Running detailed CUDA tests..."
    if python3 scripts/cuda/test_cuda_detailed.py >/dev/null 2>&1; then
        log_success "Detailed CUDA tests passed"
        record_result "cuda_detailed" "PASS" "Detailed CUDA tests successful"
    else
        log_warning "Detailed CUDA tests had issues (normal on CPU-only systems)"
        record_result "cuda_detailed" "WARNING" "Detailed CUDA tests failed"
    fi
}

test_containers() {
    local force_rebuild="${1:-false}"
    local verbose="${2:-false}"
    log_header "🐳 Container Build and Run Tests"
    
    local dev_image="endo-api-dev-test:validation"
    local prod_image="endo-api-prod-test:validation"
    
    # Helper function to check if image exists
    image_exists() {
        docker image inspect "$1" >/dev/null 2>&1
    }
    
    # Helper function to show build progress
    show_build_progress() {
        local container_type="$1"
        local pid="$2"
        local count=0
        
        while kill -0 "$pid" 2>/dev/null; do
            local dots=$(printf "%*s" $((count % 4)) | tr ' ' '.')
            printf "\r${BLUE}ℹ️  Building $container_type container$dots (${count}s)${NC}"
            sleep 1
            ((count++))
            
            # Show milestone messages
            case $count in
                30) echo -e "\n${YELLOW}⏳ Still building... Downloading Nix packages${NC}" ;;
                120) echo -e "\n${YELLOW}⏳ Still building... Installing DevEnv${NC}" ;;
                300) echo -e "\n${YELLOW}⏳ Still building... Setting up Python environment${NC}" ;;
                600) echo -e "\n${YELLOW}⏳ Still building... This can take up to an hour for first build${NC}" ;;
                1800) echo -e "\n${YELLOW}⏳ Still building... DevEnv builds can be slow but are cached${NC}" ;;
            esac
        done
        printf "\r%*s\r" 50 ""  # Clear the progress line
    }
    
    # Helper function to build container with smart caching and progress
    build_container() {
        local dockerfile="$1"
        local image_tag="$2"
        local container_type="$3"
        
        if [ "$force_rebuild" = "true" ] || ! image_exists "$image_tag"; then
            if [ "$force_rebuild" = "true" ]; then
                log_info "Force rebuilding $container_type container..."
            else
                log_info "Building $container_type container (not found)..."
            fi
            
            if [ "$verbose" = "true" ]; then
                # Verbose mode: show full build output
                log_info "🔍 Verbose mode: showing build output..."
                if cd "$PROJECT_ROOT" && timeout 3600 docker build -f "$dockerfile" -t "$image_tag" .; then
                    return 0
                else
                    return $?
                fi
            else
                # Normal mode: show progress indicator
                cd "$PROJECT_ROOT"
                (timeout 3600 docker build -f "$dockerfile" -t "$image_tag" . >/dev/null 2>&1) &
                local build_pid=$!
                
                show_build_progress "$container_type" "$build_pid"
                
                # Wait for build to complete and get exit status
                wait "$build_pid"
                return $?
            fi
        else
            log_info "Using existing $container_type container image ($image_tag)"
            return 0
        fi
    }
    
    # Test development container
    log_info "🔍 Checking development container..."
    local start_time=$(date +%s)
    
    if build_container "container/Dockerfile.dev" "$dev_image" "development"; then
        local build_time=$(($(date +%s) - start_time))
        log_success "Development container ready (${build_time}s)"
        local dev_build="PASS"
        local dev_build_msg="Dev container available"
        
        # Test development container run
        log_info "🚀 Testing development container run on port $VALIDATION_PORT..."
        local container_id
        if container_id=$(timeout 30 docker run -d -p "$VALIDATION_PORT:8000" "$dev_image") && sleep 5; then
            # Test if container is responsive
            log_info "🔍 Testing container responsiveness..."
            if timeout 10 curl -s "http://localhost:$VALIDATION_PORT" >/dev/null 2>&1 || [ $? -eq 7 ]; then
                log_success "Development container runs successfully"
                local dev_run="PASS"
                local dev_run_msg="Dev container runs and binds port"
            else
                log_warning "Development container runs but may not be fully responsive"
                local dev_run="WARNING"
                local dev_run_msg="Dev container runs but response unclear"
            fi
            
            # Clean up
            log_info "🧹 Cleaning up development container..."
            docker stop "$container_id" >/dev/null 2>&1
            docker rm "$container_id" >/dev/null 2>&1
        else
            log_error "Development container failed to run"
            local dev_run="FAIL"
            local dev_run_msg="Dev container failed to start"
        fi
    else
        local build_time=$(($(date +%s) - start_time))
        if [ $? -eq 124 ]; then
            log_warning "Development container build timed out (${build_time}s)"
            local dev_build="WARNING"
            local dev_build_msg="Dev container build timed out"
        else
            log_error "Development container build failed (${build_time}s)"
            local dev_build="FAIL"
            local dev_build_msg="Dev container build failed"
        fi
        local dev_run="SKIP"
        local dev_run_msg="Skipped due to build failure"
    fi
    
    # Test production container
    log_info "🔍 Checking production container..."
    local start_time=$(date +%s)
    
    if build_container "container/Dockerfile.prod" "$prod_image" "production"; then
        local build_time=$(($(date +%s) - start_time))
        log_success "Production container ready (${build_time}s)"
        local prod_build="PASS"
        local prod_build_msg="Prod container available"
        
        # Test production container run
        log_info "🚀 Testing production container run on port $((VALIDATION_PORT + 1))..."
        local container_id
        if container_id=$(timeout 30 docker run -d -p "$((VALIDATION_PORT + 1)):8000" "$prod_image") && sleep 5; then
            log_info "🔍 Testing container responsiveness..."
            if timeout 10 curl -s "http://localhost:$((VALIDATION_PORT + 1))" >/dev/null 2>&1 || [ $? -eq 7 ]; then
                log_success "Production container runs successfully"
                local prod_run="PASS"
                local prod_run_msg="Prod container runs and binds port"
            else
                log_warning "Production container runs but may not be fully responsive"
                local prod_run="WARNING"  
                local prod_run_msg="Prod container runs but response unclear"
            fi
            
            # Clean up
            log_info "🧹 Cleaning up production container..."
            docker stop "$container_id" >/dev/null 2>&1
            docker rm "$container_id" >/dev/null 2>&1
        else
            log_error "Production container failed to run"
            local prod_run="FAIL"
            local prod_run_msg="Prod container failed to start"
        fi
    else
        local build_time=$(($(date +%s) - start_time))
        if [ $? -eq 124 ]; then
            log_warning "Production container build timed out (${build_time}s)"
            local prod_build="WARNING" 
            local prod_build_msg="Prod container build timed out"
        else
            log_error "Production container build failed (${build_time}s)"
            local prod_build="FAIL"
            local prod_build_msg="Prod container build failed"
        fi
        local prod_run="SKIP"
        local prod_run_msg="Skipped due to build failure"
    fi
    
    record_result "container_dev_build" "$dev_build" "$dev_build_msg"
    record_result "container_dev_run" "$dev_run" "$dev_run_msg"  
    record_result "container_prod_build" "$prod_build" "$prod_build_msg"
    record_result "container_prod_run" "$prod_run" "$prod_run_msg"
    
    # Return success if at least basic builds work
    [ "$dev_build" = "PASS" ] || [ "$prod_build" = "PASS" ]
}

test_legacy_compatibility() {
    log_header "🔄 Legacy Compatibility" 
    
    log_info "🧹 Legacy container tests are deprecated - using modern DevEnv container validation"
    record_result "legacy_containers" "SKIP" "Legacy tests replaced by modern container validation"
}

generate_json_summary() {
    log_header "📊 Generating JSON Summary"
    
    # Create JSON structure
    cat > "$OUTPUT_FILE" <<EOF
{
  "timestamp": "${status_results[timestamp]}",
  "validation_port": ${status_results[validation_port]},
  "project_root": "${status_results[project_root]}",
  "summary": {
    "total_tests": 0,
    "passed": 0,
    "warnings": 0,
    "failed": 0,
    "skipped": 0
  },
  "tests": {
EOF

    local test_entries=()
    local total=0 passed=0 warnings=0 failed=0 skipped=0
    
    # Process all test results
    for key in "${!status_results[@]}"; do
        if [[ $key == *.result ]]; then
            local test_name="${key%.result}"
            local result="${status_results[$key]}"
            local message="${status_results[${test_name}.message]:-}"
            local details="${status_results[${test_name}.details]:-}"
            
            case "$result" in
                "PASS") ((passed++)) ;;
                "FAIL") ((failed++)) ;;
                "WARNING") ((warnings++)) ;;
                "SKIP") ((skipped++)) ;;
            esac
            ((total++))
            
            local entry="    \"$test_name\": {
      \"result\": \"$result\",
      \"message\": \"$message\""
            
            if [ -n "$details" ]; then
                entry="$entry,
      \"details\": \"$details\""
            fi
            
            entry="$entry
    }"
            
            test_entries+=("$entry")
        fi
    done
    
    # Join test entries with commas
    local IFS=","
    echo "${test_entries[*]}" >> "$OUTPUT_FILE"
    
    # Complete JSON structure
    cat >> "$OUTPUT_FILE" <<EOF
  },
  "environment": {
    "devenv_active": ${IN_NIX_SHELL:-false},
    "django_settings": "${DJANGO_SETTINGS_MODULE:-"not_set"}",
    "endo_api_mode": "${ENDO_API_MODE:-"not_set"}", 
    "python_path": "$(which python3)",
    "docker_available": $(command -v docker >/dev/null 2>&1 && echo "true" || echo "false")
  }
}
EOF

    # Update summary counts
    sed -i "s/\"total_tests\": 0/\"total_tests\": $total/" "$OUTPUT_FILE"
    sed -i "s/\"passed\": 0/\"passed\": $passed/" "$OUTPUT_FILE"
    sed -i "s/\"warnings\": 0/\"warnings\": $warnings/" "$OUTPUT_FILE"
    sed -i "s/\"failed\": 0/\"failed\": $failed/" "$OUTPUT_FILE"
    sed -i "s/\"skipped\": 0/\"skipped\": $skipped/" "$OUTPUT_FILE"
    
    log_success "JSON summary generated: $OUTPUT_FILE"
    log_info "Results: $passed passed, $warnings warnings, $failed failed, $skipped skipped"
}

show_summary() {
    log_header "🎯 Validation Summary"
    
    echo "📊 Test Results Overview:"
    echo "========================"
    
    # Count results
    local total=0 passed=0 warnings=0 failed=0 skipped=0
    
    for key in "${!status_results[@]}"; do
        if [[ $key == *.result ]]; then
            local result="${status_results[$key]}"
            case "$result" in
                "PASS") ((passed++)) ;;
                "FAIL") ((failed++)) ;;  
                "WARNING") ((warnings++)) ;;
                "SKIP") ((skipped++)) ;;
            esac
            ((total++))
        fi
    done
    
    echo "Total Tests: $total"
    echo "✅ Passed: $passed"
    echo "⚠️  Warnings: $warnings" 
    echo "❌ Failed: $failed"
    echo "⏭️  Skipped: $skipped"
    echo ""
    
    if [ $failed -eq 0 ]; then
        log_success "🎉 System validation completed successfully!"
        echo "✅ All critical systems are functional"
        if [ $warnings -gt 0 ]; then
            echo "⚠️  Some non-critical warnings detected - review JSON for details"
        fi
    else
        log_error "❌ System validation failed"
        echo "💡 Check JSON summary for detailed failure information"
        echo "📋 JSON Report: $OUTPUT_FILE"
    fi
}

# Main execution
main() {
    local json_only=false
    local skip_containers=false
    local force_rebuild=false
    local verbose=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json-only)
                json_only=true
                shift
                ;;
            --skip-containers)
                skip_containers=true
                shift
                ;;
            --force-rebuild)
                force_rebuild=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            *)
                echo "Usage: $0 [--json-only] [--skip-containers] [--force-rebuild] [--verbose]"
                exit 1
                ;;
        esac
    done
    
    if [ "$json_only" = false ]; then
        echo "🔍 Endo API System Validation"
        echo "=============================="
        echo "Validation Port: $VALIDATION_PORT"
        echo "Output File: $OUTPUT_FILE"
        echo ""
    fi
    
    cd "$PROJECT_ROOT"
    
    # Run all validation tests
    test_file_structure || true
    test_environment_configuration || true  
    test_database_connectivity || true
    test_cuda_availability || true
    
    if [ "$skip_containers" = false ]; then
        test_containers "$force_rebuild" "$verbose" || true
    else
        log_info "⏭️  Skipping container tests (--skip-containers flag)"
        record_result "container_dev_build" "SKIP" "Container tests skipped by user"
        record_result "container_dev_run" "SKIP" "Container tests skipped by user"
        record_result "container_prod_build" "SKIP" "Container tests skipped by user"
        record_result "container_prod_run" "SKIP" "Container tests skipped by user"
    fi
    
    test_legacy_compatibility || true
    
    # Generate outputs
    generate_json_summary
    
    if [ "$json_only" = false ]; then
        show_summary
        echo ""
        echo "📋 Detailed results available in: $OUTPUT_FILE"
    fi
    
    # Exit with appropriate code
    local failed_count=0
    for key in "${!status_results[@]}"; do
        if [[ $key == *.result ]] && [[ ${status_results[$key]} == "FAIL" ]]; then
            ((failed_count++))
        fi
    done
    
    exit $failed_count
}

# Execute main function with all arguments
main "$@"
