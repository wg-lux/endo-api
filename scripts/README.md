# Scripts Directory 🛠️

Organized utility scripts for the Endo API project, structured for maintainability and clarity.

## Directory Structure

```
scripts/
├── README.md                    # This file - comprehensive script documentation
├── core/                        # Core environment and system management
│   └── environment.py          # Unified environment settings management
├── database/                    # Database-related utilities
│   ├── ensure_psql.py          # PostgreSQL availability checker
│   ├── fetch_db_pwd_file.py    # Database password management
│   └── make_conf.py            # Configuration file generator
├── utilities/                   # General-purpose utilities
│   └── gpu-check.py            # GPU/CUDA system diagnostics
├── cuda/                        # CUDA diagnostics and troubleshooting
│   ├── README.md               # CUDA troubleshooting guide
│   ├── debug_cuda_pytorch.py   # PyTorch CUDA debugging
│   ├── minimal_cuda_test.py    # Minimal CUDA availability test
│   ├── test_cuda_detailed.py   # Comprehensive CUDA diagnostics
│   └── test_cuda_paths.py      # CUDA path and library verification
└── archive/                     # Archived/completed scripts
    ├── README.md               # Archive documentation
    ├── analyze_outdated_code.py        # One-time code analysis tool
    ├── migrate_to_unified_management.py # Migration utility (completed)
    ├── set_central_settings.py         # Legacy central settings (replaced)
    ├── set_development_settings.py     # Legacy dev settings (replaced)
    └── set_production_settings.py      # Legacy prod settings (replaced)
```

## Script Categories

### 🎯 Core Scripts (`core/`)
**Purpose**: Essential system and environment management functionality.

- **`environment.py`** - **[NEW - CONSOLIDATED SOLUTION]**
  - **Replaces**: `set_development_settings.py`, `set_production_settings.py`, `set_central_settings.py`
  - **Usage**: `python scripts/core/environment.py {development|production|central|show}`
  - **Features**: Unified environment configuration with mode switching
  - **DevEnv Integration**: Used by `devenv/scripts.nix` for environment management

### 🗄️ Database Scripts (`database/`)
**Purpose**: Database setup, configuration, and maintenance utilities.

- **`ensure_psql.py`** - PostgreSQL availability and setup verification
  - **Usage**: `python scripts/database/ensure_psql.py`
  - **DevEnv Integration**: Called by `devenv/services.nix` for database initialization

- **`fetch_db_pwd_file.py`** - Database password file management
  - **Usage**: `python scripts/database/fetch_db_pwd_file.py`
  - **Security**: Handles secure password file retrieval from `conf/db_pwd`

- **`make_conf.py`** - Configuration file generation
  - **Usage**: `python scripts/database/make_conf.py`
  - **Purpose**: Generates database configuration files from templates

### 🔧 Utilities (`utilities/`)
**Purpose**: General-purpose diagnostic and maintenance tools.

- **`gpu-check.py`** - GPU and CUDA system diagnostics
  - **Usage**: `python scripts/utilities/gpu-check.py`
  - **Purpose**: Hardware compatibility verification for ML workloads

### 🚀 CUDA Diagnostics (`cuda/`)
**Purpose**: Specialized CUDA troubleshooting and system validation.

*See `scripts/cuda/README.md` for detailed CUDA troubleshooting guide.*

### 📦 Archive (`archive/`)
**Purpose**: Completed migration tools and legacy implementations.

*See `scripts/archive/README.md` for archival documentation.*

## DevEnv Integration

These scripts are integrated with our DevEnv-based management system:

### Script References in DevEnv Configuration:
```nix
# devenv/scripts.nix
environment = "${scriptsDir}/core/environment.py";
dbSetup = "${scriptsDir}/database/ensure_psql.py";
gpuCheck = "${scriptsDir}/utilities/gpu-check.py";
```

### Management Integration:
```nix
# devenv/management.nix
scripts.core.environment
scripts.database.ensurePsql
scripts.utilities.gpuCheck
```

## Usage Examples

### Environment Management
```bash
# Set development mode
python scripts/core/environment.py development

# Set production mode  
python scripts/core/environment.py production

# Show current configuration
python scripts/core/environment.py show
```

### Database Setup
```bash
# Ensure PostgreSQL is available
python scripts/database/ensure_psql.py

# Generate configuration files
python scripts/database/make_conf.py
```

### System Diagnostics
```bash
# Check GPU/CUDA availability
python scripts/utilities/gpu-check.py

# Comprehensive CUDA diagnostics
python scripts/cuda/test_cuda_detailed.py
```

## Development Guidelines

### Adding New Scripts:
1. **Place in appropriate category directory**
2. **Add DocString with usage information**
3. **Update DevEnv configuration if needed**
4. **Add entry to this README**

### Script Requirements:
- **Python 3.12+ compatibility**
- **Clear error messages and logging**
- **Command-line argument parsing**
- **Integration with DevEnv environment**

### Code Quality Standards:
- **Type hints for function parameters**
- **Comprehensive error handling**
- **Clear usage documentation**
- **DevEnv-aware path resolution**

## Migration Notes

This reorganized structure consolidates multiple legacy scripts:

### Consolidations:
- **Environment Settings**: 3 scripts → 1 unified `core/environment.py`
- **Script Organization**: Flat structure → Categorized directories
- **Documentation**: Scattered → Centralized README system

### Backwards Compatibility:
- **DevEnv References**: All updated in `devenv/scripts.nix`
- **Legacy Access**: Original scripts archived with full functionality
- **Migration Path**: Gradual transition with dual support during migration

## Maintenance

### Regular Tasks:
1. **Review script usage** - Remove unused utilities
2. **Update DevEnv integration** - Ensure configuration alignment
3. **Archive completed tools** - Move one-time scripts to archive
4. **Performance optimization** - Profile and optimize frequently-used scripts

### Quality Assurance:
- **Test all scripts** after environment changes
- **Validate DevEnv integration** with `devenv test`
- **Review security** for database and configuration scripts
- **Document breaking changes** in implementation reports

---

*This scripts organization is part of the broader Endo API clean architecture initiative, providing maintainable and well-documented utility management.*
