# DevEnv Testing Framework

## Overview

The Endo API project uses DevEnv's native testing framework to provide comprehensive testing capabilities. This document describes how to use the testing system and what tests are available.

## Quick Start

```bash
# Run quick tests (basic functionality)
TEST_SUITE=quick devenv test

# Run specific test suites
TEST_SUITE=workflows devenv test  # Development and production workflows
TEST_SUITE=containers devenv test # Container build and runtime tests
TEST_SUITE=e2e devenv test        # End-to-end testing
TEST_SUITE=ci devenv test         # CI/CD optimized tests
TEST_SUITE=full devenv test       # Complete test suite

# Default (if no TEST_SUITE specified, runs 'quick')
devenv test
```

## Available Test Suites

### 1. Quick Tests (`quick` or `q`)
**Purpose**: Fast basic functionality verification  
**Duration**: ~3-4 seconds  
**Tests**:
- Environment setup verification
- Unified management system functionality
- Configuration system validation

**Usage**:
```bash
TEST_SUITE=quick devenv test
# or
TEST_SUITE=q devenv test
# or (default)
devenv test
```

### 2. Workflow Tests (`workflows` or `w`)
**Purpose**: Development and production workflow validation  
**Duration**: ~4-5 seconds  
**Tests**:
- Development workflow (Django dev settings)
- Production workflow (Django prod settings)  
- Database operations verification

**Usage**:
```bash
TEST_SUITE=workflows devenv test
# or
TEST_SUITE=w devenv test
```

### 3. Container Tests (`containers` or `c`)
**Purpose**: Docker container build and runtime validation  
**Duration**: Variable (depends on Docker availability)  
**Tests**:
- Container build capability
- Container runtime verification
- Gracefully handles Docker unavailability

**Usage**:
```bash
TEST_SUITE=containers devenv test
# or  
TEST_SUITE=c devenv test
```

### 4. End-to-End Tests (`e2e` or `end-to-end`)
**Purpose**: Complete workflow integration testing  
**Duration**: ~5-6 seconds  
**Tests**:
- End-to-end development setup
- End-to-end production setup
- Full Django application stack

**Usage**:
```bash
TEST_SUITE=e2e devenv test
# or
TEST_SUITE=end-to-end devenv test
```

### 5. CI Tests (`ci`)
**Purpose**: Optimized for CI/CD environments  
**Duration**: ~6-7 seconds  
**Tests**:
- Essential functionality only
- No GPU or container tests that may fail in CI
- Comprehensive but reliable test set

**Usage**:
```bash
TEST_SUITE=ci devenv test
```

### 6. Full Tests (`full`, `all`, or `f`)
**Purpose**: Complete comprehensive testing  
**Duration**: ~8-10 seconds  
**Tests**:
- All tests from all suites
- GPU support verification
- Container functionality
- Complete system validation

**Usage**:
```bash
TEST_SUITE=full devenv test
# or
TEST_SUITE=all devenv test
# or
TEST_SUITE=f devenv test
```

## Individual Test Functions

The testing framework includes these individual test functions:

### Core Tests
- `test_environment_setup`: Validates devenv environment and required tools
- `test_unified_management`: Tests Django management system functionality
- `test_configuration_system`: Verifies configuration files and environment variables

### Workflow Tests
- `test_development_workflow`: Tests development server and settings
- `test_production_workflow`: Tests production configuration
- `test_database_operations`: Validates database configuration and connectivity

### Integration Tests
- `test_container_build`: Tests Docker container build capability
- `test_container_runtime`: Tests Docker runtime environment
- `test_e2e_development`: End-to-end development workflow
- `test_e2e_production`: End-to-end production workflow

### Compatibility Tests
- `test_backwards_compatibility`: Ensures direct Django management still works
- `test_gpu_support`: Tests GPU detection and support

## Test Output

The testing system provides colored output with clear status indicators:

- 🧪 **Test suite header** with suite name
- ℹ️  **Info messages** (blue) for test progress
- ✅ **Success messages** (green) for passed tests
- ⚠️  **Warning messages** (yellow) for skipped/optional tests
- ❌ **Error messages** (red) for failed tests

## Exit Codes

The testing system uses standard exit codes:
- `0`: All tests passed
- `1`: One or more tests failed

DevEnv will report "Tests passed :)" or "Tests failed :(" accordingly.

## Integration with DevEnv

The testing is integrated using DevEnv's `enterTest` attribute in `devenv.nix`:

```nix
enterTest = ''
  # Source common test functions
  source ${./test-functions.sh}
  
  # Run the test suite based on TEST_SUITE environment variable
  test_suite=''${TEST_SUITE:-quick}
  
  echo "🧪 Running DevEnv Test Suite: $test_suite"
  echo "========================================="
  
  # ... test execution logic
'';
```

## Test Function Development

Test functions are defined in `test-functions.sh` and follow this pattern:

```bash
test_example_functionality() {
    # Test logic here
    [ -f "required_file" ] || { echo "Required file missing"; return 1; }
    
    # More tests...
    
    echo "Example functionality verified"
    return 0
}
```

Each test suite function calls individual tests with proper error handling:

```bash
run_example_suite() {
    test_info "Running Example Test Suite..."
    
    local suite_failed=0
    
    run_single_test "example" "Example Test" test_example_functionality || suite_failed=1
    
    test_success "Example tests completed: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [ $suite_failed -eq 1 ]; then
        test_error "Some tests failed in example test suite"
        return 1
    fi
    
    return 0
}
```

## Troubleshooting

### Common Issues

1. **Tests fail with "Django not importable"**
   - Ensure you're in a devenv shell: `devenv shell`
   - Check Python dependencies are installed: `uv sync`

2. **Container tests are skipped**
   - This is normal if Docker is not available
   - Install Docker if container testing is required

3. **Tests pass but devenv reports failure**
   - Check exit codes in test functions
   - Ensure all test suite functions return proper exit codes

### Debug Mode

For debugging individual test functions:

```bash
# Source the test functions directly
source test-functions.sh

# Run individual tests
test_environment_setup
test_unified_management

# Or run specific suites
run_quick_tests
```

## Continuous Integration

For CI/CD pipelines, use the `ci` test suite:

```yaml
# Example GitHub Actions
- name: Run DevEnv Tests
  run: TEST_SUITE=ci devenv test
```

The CI suite is optimized to:
- Skip tests that require GPU or Docker
- Focus on essential functionality
- Provide reliable results in CI environments

## Performance

Test suite performance (approximate):

| Suite | Duration | Tests | Best For |
|-------|----------|-------|----------|
| quick | 3-4s | 3 | Development feedback |
| workflows | 4-5s | 3 | Workflow validation |
| containers | Variable | 2 | Docker testing |
| e2e | 5-6s | 2 | Integration testing |
| ci | 6-7s | 6 | CI/CD pipelines |
| full | 8-10s | 12 | Comprehensive validation |

## Future Enhancements

Planned improvements:
- Parallel test execution for faster full suite runs
- Integration with external testing tools
- Database migration testing
- Performance benchmarking tests
- Custom test configuration options

---

For more information about DevEnv testing, see: https://devenv.sh/tests/
