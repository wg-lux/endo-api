#!/usr/bin/env bash
# Container management script for development
# Usage: ./container-dev.sh [build|run|stop|logs|restart]

set -e

ACTION=${1:-"run"}

case $ACTION in
  "build")
    echo "🔨 Building development container..."
    ./switch-mode.sh dev
    devenv container build endo-api-dev
    devenv container copy endo-api-dev
    echo "✅ Development container built and copied to Docker!"
    ;;
    
  "run")
    echo "🚀 Running development container..."
    ./switch-mode.sh dev
    
    # Build if not exists
    if ! docker image inspect endo-api-dev:latest &>/dev/null; then
      echo "Container image not found, building first..."
      devenv container build endo-api-dev
      devenv container copy endo-api-dev
    fi
    
    # Stop existing container
    docker stop endo-api-dev 2>/dev/null || true
    docker rm endo-api-dev 2>/dev/null || true
    
    # Run new container
    docker run -d \
      --name endo-api-dev \
      --restart unless-stopped \
      -p 8118:8118 \
      -e ENDO_API_MODE=development \
      -v "$(pwd)/data:/app/data" \
      -v "$(pwd)/conf:/app/conf" \
      -v "$(pwd)/data/logs:/app/logs" \
      endo-api-dev:latest
    
    echo "✅ Development container started!"
    echo "   - URL: http://localhost:8118"
    echo "   - Logs: docker logs -f endo-api-dev"
    ;;
    
  "stop")
    echo "🛑 Stopping development container..."
    docker stop endo-api-dev 2>/dev/null || true
    docker rm endo-api-dev 2>/dev/null || true
    echo "✅ Development container stopped!"
    ;;
    
  "logs")
    echo "📋 Following development container logs..."
    docker logs -f endo-api-dev
    ;;
    
  "restart")
    echo "🔄 Restarting development container..."
    $0 stop
    $0 run
    ;;
    
  *)
    echo "Usage: $0 [build|run|stop|logs|restart]"
    echo ""
    echo "Commands:"
    echo "  build   - Build the development container"
    echo "  run     - Run the development container (default)"
    echo "  stop    - Stop and remove the container"
    echo "  logs    - Follow container logs"
    echo "  restart - Stop and start the container"
    exit 1
    ;;
esac
