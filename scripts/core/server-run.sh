#!/usr/bin/env bash
# Unified server startup script (DRY)
# - Detects mode (prefers .mode, falls back to ENDO_API_MODE)
# - Ensures environment is initialized (.env, conf)
# - Honors DJANGO_HOST/DJANGO_PORT at runtime to avoid rebuilds
# - Starts appropriate server (daphne in prod if available, dev runserver otherwise)
set -eo pipefail

# Detect mode: prefer .mode, fallback to ENDO_API_MODE, default development
if [ -f .mode ] && MODE_FILE=$(cat .mode 2>/dev/null | tr -d '\n' | tr -d ' '); then
  export ENDO_API_MODE=${MODE_FILE:-development}
else
  export ENDO_API_MODE=${ENDO_API_MODE:-development}
fi

# Runtime configuration (favor environment to avoid rebuilds)
HOST="${DJANGO_HOST:-127.0.0.1}"
PORT="${DJANGO_PORT:-8118}"
DJANGO_MODULE_RUNTIME="${DJANGO_MODULE:-endo_api}"

echo "🌟 Starting Endo API Server"
echo "Mode: ${ENDO_API_MODE}"
echo "Host: ${HOST}"
echo "Port: ${PORT}"
echo ""

# Ensure environment is ready
if [ ! -f ".env" ]; then
  echo "📝 Environment file missing, running setup..."
  if command -v manage >/dev/null 2>&1; then
    manage setup
  else
    # Fallback: attempt direct setup pipeline
    if command -v uv >/dev/null 2>&1; then
      uv run python scripts/core/setup.py || true
      uv run python scripts/database/make_conf.py || true
    else
      python scripts/core/setup.py || true
      python scripts/database/make_conf.py || true
    fi
  fi
fi

# Helper to run python via uv when available
py() {
  if command -v uv >/dev/null 2>&1; then
    uv run python "$@"
  else
    python "$@"
  fi
}

run_daphne() {
  if command -v uv >/dev/null 2>&1; then
    uv run daphne -b "$HOST" -p "$PORT" "${DJANGO_MODULE_RUNTIME}.asgi:application"
  elif command -v daphne >/dev/null 2>&1; then
    daphne -b "$HOST" -p "$PORT" "${DJANGO_MODULE_RUNTIME}.asgi:application"
  else
    echo "⚠️  Daphne not available, falling back to Django runserver"
    py manage.py runserver "$HOST:$PORT" --noreload
  fi
}

if [ "$ENDO_API_MODE" = "production" ]; then
  echo "🚀 Production pipeline: migrate, load base data, collectstatic"
  py manage.py migrate --noinput || { echo "❌ migrate failed"; exit 1; }
  # Load base data if command exists
  if py manage.py help | grep -q "load_base_db_data"; then
    py manage.py load_base_db_data || echo "⚠️ load_base_db_data failed or skipped"
  fi
  py manage.py collectstatic --noinput || echo "⚠️ collectstatic warnings"

  echo "🏁 Starting ASGI server (Daphne if available)"
  run_daphne
else
  echo "🛠️  Development mode: migrate and run dev server"
  py manage.py migrate || echo "⚠️ migration warnings"
  py manage.py runserver "$HOST:$PORT"
fi
