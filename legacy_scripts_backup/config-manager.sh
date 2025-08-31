#!/usr/bin/env bash
# Configuration Management Script for EndoReg API
# Usage: ./config-manager.sh [set-port|set-host|set-module|show-config] [value]

set -e

CONFIG_FILE="app_config.nix"

show_usage() {
    echo "Configuration Management for EndoReg API"
    echo "========================================"
    echo ""
    echo "Usage: $0 <command> [value]"
    echo ""
    echo "Commands:"
    echo "  show-config           Show current configuration"
    echo "  set-port <port>      Change server port (e.g., 8080)"
    echo "  set-host <host>      Change server host (e.g., 0.0.0.0)"
    echo "  set-module <name>    Change Django module name (e.g., my_api)"
    echo "  set-app-name <name>  Change application name (e.g., my-app)"
    echo ""
    echo "Examples:"
    echo "  $0 show-config"
    echo "  $0 set-port 8080"
    echo "  $0 set-host 0.0.0.0"
    echo "  $0 set-module my_api"
    echo "  $0 set-app-name my-app"
    echo ""
    echo "After making changes, restart your development environment:"
    echo "  direnv reload"
    echo "  devenv shell"
}

show_config() {
    echo "Current Configuration:"
    echo "====================="
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Configuration file $CONFIG_FILE not found!"
        exit 1
    fi
    
    # Use nix-instantiate for more reliable parsing
    if command -v nix-instantiate >/dev/null 2>&1; then
        echo "📝 Reading from: $CONFIG_FILE"
        echo ""
        
        # Read values using nix-instantiate for accuracy
        get_config_value() {
            local path="$1"
            local description="$2"
            local value=$(nix-instantiate --eval --strict --json "$CONFIG_FILE" -A "$path" 2>/dev/null | sed 's/"//g')
            if [ $? -eq 0 ] && [ -n "$value" ] && [ "$value" != "null" ]; then
                printf "%-20s %s\n" "$description:" "$value"
            else
                printf "%-20s %s\n" "$description:" "❌ Not found"
            fi
        }
        
        get_config_value "app.name" "Application Name"
        get_config_value "app.djangoModule" "Django Module"
        get_config_value "app.version" "Version"
        echo ""
        get_config_value "server.host" "Server Host"
        get_config_value "server.port" "Server Port"
        get_config_value "server.protocol" "Protocol"
        get_config_value "server.containerHost" "Container Host"
        echo ""
        get_config_value "database.dev.engine" "Dev Database"
        get_config_value "database.prod.engine" "Prod Database"
        echo ""
        get_config_value "services.postgres.port" "PostgreSQL Port"
        get_config_value "services.redis.port" "Redis Port"
        
    else
        # Fallback to grep/sed if nix-instantiate not available
        echo "⚠️  Using fallback parsing (nix-instantiate not found)"
        echo ""
        echo "Application Name: $(grep -A1 'app = {' "$CONFIG_FILE" | grep 'name' | sed 's/.*name = "\(.*\)";.*/\1/')"
        echo "Django Module:    $(grep -A2 'app = {' "$CONFIG_FILE" | grep 'djangoModule' | sed 's/.*djangoModule = "\(.*\)";.*/\1/')"
        echo "Server Host:      $(grep -A1 'server = {' "$CONFIG_FILE" | grep 'host' | sed 's/.*host = "\(.*\)";.*/\1/')"
        echo "Server Port:      $(grep -A2 'server = {' "$CONFIG_FILE" | grep 'port' | sed 's/.*port = "\(.*\)";.*/\1/')"
        echo "Protocol:         $(grep -A3 'server = {' "$CONFIG_FILE" | grep 'protocol' | sed 's/.*protocol = "\(.*\)";.*/\1/')"
    fi
}

set_value() {
    local section="$1"
    local key="$2"
    local value="$3"
    
    echo "Setting $section.$key = \"$value\""
    
    # Validate that the file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Configuration file $CONFIG_FILE not found!"
        exit 1
    fi
    
    # Create backup before making changes
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Use sed to update the value in place
    # More robust pattern matching to handle various formatting
    if sed -i "s/\\(${key}[[:space:]]*=[[:space:]]*\"\\)[^\"]*\\(\";\\)/\\1${value}\\2/" "$CONFIG_FILE"; then
        echo "✅ Configuration updated successfully!"
        echo ""
        echo "🔄 To apply changes:"
        echo "  1. direnv reload"
        echo "  2. devenv shell"
        echo ""
        echo "🐳 If using containers, rebuild them:"
        echo "     container-build-dev"
        echo "     container-build-prod"
        echo ""
        echo "📋 Backup created: ${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    else
        echo "❌ Failed to update configuration"
        echo "   This might happen if the key pattern doesn't match exactly"
        echo "   Please check the file manually or use a different approach"
        exit 1
    fi
}

validate_config() {
    echo "Validating Configuration:"
    echo "========================"
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Configuration file $CONFIG_FILE not found!"
        return 1
    fi
    
    # Check Nix syntax
    if command -v nix-instantiate >/dev/null 2>&1; then
        echo "🔍 Checking Nix syntax..."
        if nix-instantiate --parse "$CONFIG_FILE" >/dev/null 2>&1; then
            echo "✅ Nix syntax is valid"
        else
            echo "❌ Nix syntax errors found"
            nix-instantiate --parse "$CONFIG_FILE"
            return 1
        fi
        
        echo "🔍 Checking required configuration values..."
        local failed=0
        
        check_config_path() {
            local path="$1"
            local description="$2"
            if nix-instantiate --eval --strict --json "$CONFIG_FILE" -A "$path" >/dev/null 2>&1; then
                echo "✅ $description"
            else
                echo "❌ $description (missing: $path)"
                failed=1
            fi
        }
        
        check_config_path "app.name" "Application name"
        check_config_path "app.djangoModule" "Django module"
        check_config_path "server.host" "Server host"
        check_config_path "server.port" "Server port"
        check_config_path "database.dev.engine" "Development database"
        check_config_path "database.prod.engine" "Production database"
        
        if [ $failed -eq 0 ]; then
            echo ""
            echo "🎉 Configuration is valid!"
            return 0
        else
            echo ""
            echo "❌ Configuration validation failed"
            return 1
        fi
    else
        echo "⚠️  Cannot validate: nix-instantiate not found"
        echo "   Please ensure Nix is installed and available"
        return 1
    fi
}

case "${1:-help}" in
    "show-config")
        show_config
        ;;
    "validate")
        validate_config
        ;;
    "set-port")
        if [ -z "$2" ]; then
            echo "❌ Please specify a port number"
            echo "Usage: $0 set-port <port>"
            exit 1
        fi
        set_value "server" "port" "$2"
        ;;
    "set-host")
        if [ -z "$2" ]; then
            echo "❌ Please specify a host"
            echo "Usage: $0 set-host <host>"
            exit 1
        fi
        set_value "server" "host" "$2"
        ;;
    "set-module")
        if [ -z "$2" ]; then
            echo "❌ Please specify a Django module name"
            echo "Usage: $0 set-module <name>"
            exit 1
        fi
        set_value "app" "djangoModule" "$2"
        echo ""
        echo "⚠️  Note: Changing Django module name requires additional steps:"
        echo "  1. Rename the Django project directory from 'endo_api' to '$2'"
        echo "  2. Update imports in your Python code"
        echo "  3. Update ASGI/WSGI application references"
        ;;
    "set-app-name")
        if [ -z "$2" ]; then
            echo "❌ Please specify an application name"
            echo "Usage: $0 set-app-name <name>"
            exit 1
        fi
        set_value "app" "name" "$2"
        echo ""
        echo "ℹ️  This changes the container names and application identity."
        echo "   Existing containers will need to be rebuilt."
        ;;
    "help"|*)
        show_usage
        ;;
esac
