#!/usr/bin/env bash

# Mode switching script for endo-api development environment
# Usage: ./switch-mode.sh [dev|prod]

set -e

MODE=${1:-dev}

if [ "$MODE" != "dev" ] && [ "$MODE" != "prod" ]; then
    echo "Usage: $0 [dev|prod]"
    echo "  dev  - Development mode (SQLite, local services)"
    echo "  prod - Production mode (PostgreSQL, external services)"
    exit 1
fi

echo "Switching to $MODE mode..."

# Create/update .mode file and set environment variable
if [ "$MODE" = "dev" ]; then
    echo "development" > .mode
    export ENDO_API_MODE=development
    # Update current shell and create export for direnv
    echo "export ENDO_API_MODE=development" > .mode-env
    echo "Development mode activated:"
    echo "  - Database: SQLite (./data/db.sqlite3)"
    echo "  - Services: Local PostgreSQL and Redis available"
    echo "  - Server: Binds to localhost"
elif [ "$MODE" = "prod" ]; then
    echo "production" > .mode
    export ENDO_API_MODE=production  
    # Update current shell and create export for direnv
    echo "export ENDO_API_MODE=production" > .mode-env
    echo "Production mode activated:"
    echo "  - Database: PostgreSQL (external)"
    echo "  - Services: External PostgreSQL and Redis expected"
    echo "  - Server: Binds to 0.0.0.0"
fi

echo ""
echo "Mode switch complete. Running 'direnv reload' to apply changes..."

# Automatically reload direnv (this will pick up the .mode file change)
direnv reload

echo ""
echo "Available commands:"
echo "  - devenv shell          # Enter development shell"
echo "  - run-server            # Start server (adapts to current mode)"
echo "  - start-services        # Start services (adapts to current mode)"
echo "  - services-up           # Start background services only"
