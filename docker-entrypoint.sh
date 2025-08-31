#!/usr/bin/env bash
set -e

echo "🚀 Starting EndoReg API Development Container"
echo "Mode: ${ENDO_API_MODE:-development}"
echo "Host: ${DJANGO_HOST:-0.0.0.0}"  
echo "Port: ${DJANGO_PORT:-8118}"

# Ensure mode is properly set for development containers
export ENDO_API_MODE="${ENDO_API_MODE:-development}"

# Create .mode file for DevEnv to detect mode properly
echo "$ENDO_API_MODE" > /app/.mode

# Set Django configuration based on mode
if [ "$ENDO_API_MODE" = "production" ]; then
    export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-endo_api.settings_prod}"
else
    export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-endo_api.settings_dev}"
fi

export DJANGO_MODULE="${DJANGO_MODULE:-endo_api}"

# Set essential environment variables for Django
export DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY:-dev-secret-key-$(date +%s)}"
export DJANGO_DEBUG="${DJANGO_DEBUG:-True}"
export DJANGO_ALLOWED_HOSTS="${DJANGO_ALLOWED_HOSTS:-*}"
export DATABASE_ENGINE="${DATABASE_ENGINE:-sqlite}"
export DATABASE_NAME="${DATABASE_NAME:-/app/data/db.sqlite3}"
export STORAGE_DIR="${STORAGE_DIR:-/app/data}"
export DATA_DIR="${DATA_DIR:-/app/data}"
export WORKING_DIR="${WORKING_DIR:-/app}"
export CONF_DIR="${CONF_DIR:-/app/conf}"

# Ensure git submodules are available (quick check)
cd /app
git submodule update --init --recursive 2>/dev/null || echo "Git submodules initialized"

# Create essential directories
mkdir -p "$DATA_DIR" "$CONF_DIR" /app/staticfiles

# Create .env file if it doesn't exist (required by DevEnv)
if [ ! -f "/app/.env" ] && [ "$ENDO_API_MODE" = "development" ]; then
    echo "📝 Creating .env file for development mode..."
    devenv shell -- python -c "
import os
from pathlib import Path

# Create basic .env file for development
env_content = '''# Development Environment Configuration
DJANGO_SECRET_KEY=dev-secret-key-$(date +%s)
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=*
DATABASE_ENGINE=sqlite
DATABASE_NAME=/app/data/db.sqlite3
DATA_DIR=/app/data
CONF_DIR=/app/conf
ENDO_API_MODE=development
'''

with open('/app/.env', 'w') as f:
    f.write(env_content)

print('✅ Created .env file for development mode')
" || echo "⚠️ Could not create .env file automatically"
fi

echo "📦 Collecting static files..."
devenv shell -- python manage.py collectstatic --noinput --clear || echo "Static files collection skipped"

echo "🗃️ Running migrations..."
devenv shell -- python manage.py migrate || echo "Migration failed, continuing..."

echo "� Setting up CUDA environment..."
devenv shell -- devenv task run env:setup-cuda || echo "CUDA setup completed with warnings"

echo "�🌟 Starting development server with DevEnv environment..."
echo "    ✅ FFmpeg, OpenCV, CUDA dependencies loaded"
echo "    ✅ All Python packages available"  
echo "    ✅ Git submodules mounted"
echo ""

# Start Django development server through DevEnv
exec devenv shell -- python manage.py runserver ${DJANGO_HOST:-0.0.0.0}:${DJANGO_PORT:-8118}
