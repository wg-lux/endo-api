#!/usr/bin/env bash
# Production deployment script
# Usage: ./deploy-prod.sh

set -e

echo "🚀 Endo API Production Deployment (Native DevEnv)"
echo "================================================"

# Switch to production mode
echo "1. Switching to production mode..."
./switch-mode.sh prod

# Build and copy production container to Docker
echo "2. Building and preparing production container..."
devenv container build endo-api-prod
devenv container copy endo-api-prod

# Run the production container using Docker directly
echo "3. Running production container..."
echo "Stopping any existing container..."
docker stop endo-api-prod 2>/dev/null || true
docker rm endo-api-prod 2>/dev/null || true

echo "Starting production container..."
docker run -d \
  --name endo-api-prod \
  --restart unless-stopped \
  -p 8118:8118 \
  -e ENDO_API_MODE=production \
  -v "$(pwd)/data:/app/data" \
  -v "$(pwd)/conf:/app/conf" \
  -v "$(pwd)/data/logs:/app/logs" \
  endo-api-prod:latest

echo ""
echo "✅ Production deployment complete!"
echo ""
echo "Service URLs:"
echo "  - API Server: http://localhost:8118"
echo ""
echo "Management commands:"
echo "  - View logs: docker logs -f endo-api-prod"
echo "  - Stop service: docker stop endo-api-prod"
echo "  - Restart: docker restart endo-api-prod"
echo "  - Remove: docker rm -f endo-api-prod"
