# Legacy Testing Scripts

This directory contains legacy testing scripts that were used before the unified DevEnv testing framework. These are kept for backwards compatibility and documentation purposes.

## Status: **Legacy/Deprecated**

⚠️ **These scripts are superseded by the unified DevEnv testing system.** 

Use `manage test <suite>` commands instead for current testing.

## Available Scripts

### `test-runner.sh` 
**Legacy test runner** - Used by `manage test legacy` command
- **Current Alternative**: `manage test <suite>` or `devenv test`
- **Status**: Still functional for backwards compatibility

### `test-functions.sh`
**Common test functions** - Sourced by DevEnv's `enterTest` system
- **Status**: Still used by DevEnv testing framework

### `test-containers.sh`
**Legacy container testing** - Comprehensive container validation
- **Current Alternative**: `manage test containers` or `devenv tasks run container:*`
- **Status**: Deprecated, use unified management commands

### `test-container-functionality.sh`
**Legacy functionality tests** - Container functionality validation
- **Current Alternative**: `manage build && manage run && manage status`
- **Status**: Deprecated

### `test-clean-implementation.sh`
**Legacy implementation tests** - Clean architecture validation
- **Current Alternative**: `manage test full`
- **Status**: Deprecated

## Migration Guide

### Old → New Commands

```bash
# Legacy approach
./test-containers.sh         → manage test containers
./test-runner.sh full        → manage test full  
./test-clean-implementation  → manage test e2e

# New unified approach
manage test quick            # Quick core functionality tests
manage test workflows        # Development/production workflow tests  
manage test containers       # Container build and runtime tests
manage test e2e              # End-to-end workflow tests
manage test full             # Complete test suite
manage test ci               # CI/CD compatible tests
```

## When to Use Legacy Scripts

1. **Debugging**: When the unified system fails and you need to isolate issues
2. **Documentation**: Understanding how the original testing worked
3. **Migration**: Gradually migrating custom test logic to the unified system

## Removal Timeline

These scripts will be removed in a future version once:
- [ ] All functionality is confirmed to work in the unified system
- [ ] Documentation is fully updated
- [ ] CI/CD pipelines are migrated to use unified commands

---

**Recommendation**: Use the unified DevEnv testing system (`manage test <suite>`) for all new development and testing workflows.
