#!/usr/bin/env bash
set -e

echo "🚀 Starting EndoReg API Production Container"
echo "Env: ${DJANGO_ENV:-production}"
echo "Host: ${DJANGO_HOST:-0.0.0.0}"
echo "Port: ${DJANGO_PORT:-8118}"

# Set production Django configuration
export DJANGO_ENV="${DJANGO_ENV:-production}"
export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-endo_api.settings_prod}"
export DJANGO_MODULE="${DJANGO_MODULE:-endo_api}"

# Production environment variables
export DJANGO_DEBUG="${DJANGO_DEBUG:-False}"
export DJANGO_ALLOWED_HOSTS="${DJANGO_ALLOWED_HOSTS:-*}"
export STORAGE_DIR="${STORAGE_DIR:-/app/data}"
export DATA_DIR="${DATA_DIR:-/app/data}"
export WORKING_DIR="${WORKING_DIR:-/app}"

# Ensure essential directories exist (no credentials required via volumes)
mkdir -p "$DATA_DIR" /app/staticfiles

# Validate critical environment variables
if [ -z "${DJANGO_SECRET_KEY:-}" ]; then
    echo "❌ DJANGO_SECRET_KEY must be set in production"
    exit 1
fi

# Database migrations (env-driven config)
echo "🗄️ Running database migrations..."
python manage.py migrate --noinput || echo "⚠️ Migrations failed, continuing..."

# Health check
echo "🏥 Running production health check..."
python manage.py check --deploy || echo "⚠️ Health check warnings detected"

echo "🌟 Starting production server..."
HOST="${DJANGO_HOST:-0.0.0.0}"
PORT="${DJANGO_PORT:-8118}"

# Prefer Daphne (ASGI); fallback to Django runserver
if command -v daphne >/dev/null 2>&1; then
  echo "🚀 Using Daphne ASGI server (production-ready)"
  exec daphne -b "$HOST" -p "$PORT" "${DJANGO_MODULE}.asgi:application"
else
  echo "⚠️ Daphne not found, falling back to Django runserver"
  exec python manage.py runserver "$HOST:$PORT" --noreload
fi
