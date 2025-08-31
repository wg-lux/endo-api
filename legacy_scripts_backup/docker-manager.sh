#!/usr/bin/env bash
# Docker Container Management Script for EndoReg API
# ================================================
# 
# This script provides easy container management with configuration
# sourced from app_config.nix for consistency.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source configuration from app_config.nix
get_config_value() {
    local path="$1"
    # Use Python for JSON parsing instead of jq for better compatibility
    nix eval --json --file "$PROJECT_ROOT/app_config.nix" | python3 -c "
import json, sys
data = json.load(sys.stdin)
path_parts = '$path'.strip('.').split('.')
value = data
for part in path_parts:
    if part and part in value:
        value = value[part]
    else:
        print('null', file=sys.stderr)
        sys.exit(1)
print(value)
"
}

# Load configuration
APP_NAME=$(get_config_value '.app.name')
DJANGO_MODULE=$(get_config_value '.app.djangoModule')
SERVER_HOST=$(get_config_value '.server.host')
SERVER_PORT=$(get_config_value '.server.port')
CONTAINER_HOST=$(get_config_value '.server.containerHost')
POSTGRES_VERSION=$(get_config_value '.services.postgres.version')
POSTGRES_PORT=$(get_config_value '.services.postgres.port')
REDIS_VERSION=$(get_config_value '.services.redis.version')
REDIS_PORT=$(get_config_value '.services.redis.port')
DB_NAME=$(get_config_value '.database.prod.name')
DB_USER=$(get_config_value '.database.prod.user')

# Docker image names
DEV_IMAGE="${APP_NAME}-dev"
PROD_IMAGE="${APP_NAME}-prod"

print_header() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}  EndoReg API Container Manager${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

print_config() {
    echo -e "${BLUE}Current Configuration:${NC}"
    echo "  App Name: $APP_NAME"
    echo "  Django Module: $DJANGO_MODULE"
    echo "  Server Port: $SERVER_PORT"
    echo "  Container Host: $CONTAINER_HOST"
    echo "  PostgreSQL: $POSTGRES_VERSION (port $POSTGRES_PORT)"
    echo "  Redis: $REDIS_VERSION (port $REDIS_PORT)"
    echo ""
}

build_image() {
    local mode="$1"
    local dockerfile="Dockerfile.$mode"
    local image_name="${APP_NAME}-${mode}"
    
    echo -e "${BLUE}Building $mode container image...${NC}"
    
    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Error: $dockerfile not found${NC}"
        exit 1
    fi
    
    docker build \
        --build-arg DJANGO_MODULE="$DJANGO_MODULE" \
        --build-arg DJANGO_PORT="$SERVER_PORT" \
        --build-arg DJANGO_HOST="$CONTAINER_HOST" \
        -f "$dockerfile" \
        -t "$image_name" \
        .
    
    echo -e "${GREEN}✅ Built $image_name successfully${NC}"
}

run_container() {
    local mode="$1"
    local image_name="${APP_NAME}-${mode}"
    local container_name="${APP_NAME}-${mode}-test"
    
    echo -e "${BLUE}Running $mode container...${NC}"
    
    # Stop and remove existing container if it exists (running or stopped)
    if docker ps -aq -f name="$container_name" | grep -q .; then
        echo "Stopping and removing existing container..."
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
    fi
    
    # Check if NVIDIA runtime is available for GPU support
    local gpu_args=""
    if command -v nvidia-smi &> /dev/null; then
        if docker info 2>/dev/null | grep -q "nvidia"; then
            gpu_args="--gpus all"
            echo "🎯 NVIDIA GPU support detected - enabling Docker GPU access"
        elif command -v podman &> /dev/null; then
            # For Podman, mount all necessary NVIDIA devices and set environment variables
            gpu_args="--device /dev/nvidia0:/dev/nvidia0 --device /dev/nvidiactl:/dev/nvidiactl --device /dev/nvidia-uvm:/dev/nvidia-uvm --device /dev/nvidia-modeset:/dev/nvidia-modeset"
            # Add CUDA environment variables for proper runtime detection
            gpu_args="$gpu_args -e CUDA_VISIBLE_DEVICES=all -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility"
            echo "🎯 NVIDIA GPU detected - enabling Podman GPU access via device mounting"
        else
            echo "⚠️ NVIDIA GPU detected but container GPU support not configured"
            echo "   To enable GPU: Install nvidia-container-toolkit"
        fi
    fi
    
    # Run container
    docker run -d \
        --name "$container_name" \
        -p "${SERVER_PORT}:${SERVER_PORT}" \
        $gpu_args \
        -e DJANGO_MODULE="$DJANGO_MODULE" \
        -e DJANGO_PORT="$SERVER_PORT" \
        -e DJANGO_HOST="$CONTAINER_HOST" \
        -e ENDO_API_MODE="$mode" \
        -v "$PROJECT_ROOT/data:/app/data" \
        -v "$PROJECT_ROOT/conf:/app/conf" \
        "$image_name"
    
    echo -e "${GREEN}✅ Started $container_name${NC}"
    echo "Container logs: docker logs -f $container_name"
    echo "Stop container: docker stop $container_name"
    echo "Access: http://localhost:$SERVER_PORT"
}

test_container() {
    local mode="$1"
    local container_name="${APP_NAME}-${mode}-test"
    
    echo -e "${BLUE}Testing $mode container...${NC}"
    
    # Wait for container to start
    echo "Waiting for container to be ready..."
    sleep 5
    
    # Check if container is running
    if ! docker ps -q -f name="$container_name" | grep -q .; then
        echo -e "${RED}❌ Container is not running${NC}"
        echo "Container logs:"
        docker logs "$container_name" 2>&1 || true
        return 1
    fi
    
    # Test HTTP endpoint
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://localhost:$SERVER_PORT" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Container is responding on port $SERVER_PORT${NC}"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: Waiting for server to start..."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}❌ Container did not respond after $max_attempts attempts${NC}"
    echo "Container logs:"
    docker logs "$container_name" 2>&1 || true
    return 1
}

stop_containers() {
    local mode="${1:-}"
    local remove_flag="${2:-}"
    
    if [ -n "$mode" ]; then
        echo -e "${BLUE}Stopping $mode container...${NC}"
        local container_name="${APP_NAME}-${mode}-test"
        if docker ps -q -f name="$container_name" | grep -q .; then
            docker stop "$container_name" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ Stopped $container_name${NC}"
            
            if [ "$remove_flag" = "remove" ]; then
                docker rm "$container_name" >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ Removed $container_name${NC}"
            else
                echo -e "${YELLOW}Container stopped but not removed. Use 'remove-$mode' to remove it.${NC}"
            fi
        else
            echo -e "${YELLOW}No running $mode container found${NC}"
        fi
    else
        echo -e "${BLUE}Stopping all test containers...${NC}"
        
        for mode_name in dev prod; do
            local container_name="${APP_NAME}-${mode_name}-test"
            if docker ps -q -f name="$container_name" | grep -q .; then
                docker stop "$container_name" >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ Stopped $container_name${NC}"
                
                if [ "$remove_flag" = "remove" ]; then
                    docker rm "$container_name" >/dev/null 2>&1 || true
                    echo -e "${GREEN}✅ Removed $container_name${NC}"
                fi
            fi
        done
        
        if [ "$remove_flag" != "remove" ]; then
            echo -e "${YELLOW}Containers stopped but not removed. Use 'remove-all' to remove them.${NC}"
        fi
    fi
}

remove_containers() {
    local mode="${1:-}"
    
    if [ -n "$mode" ]; then
        echo -e "${BLUE}Removing $mode container...${NC}"
        local container_name="${APP_NAME}-${mode}-test"
        if docker ps -aq -f name="$container_name" | grep -q .; then
            docker stop "$container_name" >/dev/null 2>&1 || true
            docker rm "$container_name" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ Removed $container_name${NC}"
        else
            echo -e "${YELLOW}No $mode container found${NC}"
        fi
    else
        echo -e "${BLUE}Removing all test containers...${NC}"
        
        for mode_name in dev prod; do
            local container_name="${APP_NAME}-${mode_name}-test"
            if docker ps -aq -f name="$container_name" | grep -q .; then
                docker stop "$container_name" >/dev/null 2>&1 || true
                docker rm "$container_name" >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ Removed $container_name${NC}"
            fi
        done
    fi
}

cleanup_images() {
    echo -e "${BLUE}Cleaning up container images...${NC}"
    
    for mode in dev prod; do
        local image_name="${APP_NAME}-${mode}"
        if docker images -q "$image_name" | grep -q .; then
            docker rmi "$image_name" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ Removed $image_name${NC}"
        fi
    done
}

exec_container() {
    local mode="$1"
    shift
    local container_name="${APP_NAME}-${mode}-test"
    
    if ! docker ps -q -f name="$container_name" | grep -q .; then
        echo -e "${RED}❌ Container $container_name is not running${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Executing command in $container_name...${NC}"
    docker exec -it "$container_name" sh -c "$*"
}

shell_container() {
    local mode="$1"
    local container_name="${APP_NAME}-${mode}-test"
    
    if ! docker ps -q -f name="$container_name" | grep -q .; then
        echo -e "${RED}❌ Container $container_name is not running${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Opening shell in $container_name...${NC}"
    docker exec -it "$container_name" sh
}

full_test() {
    echo -e "${BLUE}Running full container test suite...${NC}"
    echo ""
    
    local success=true
    
    for mode in dev prod; do
        echo -e "${YELLOW}Testing $mode mode...${NC}"
        
        if build_image "$mode" && run_container "$mode" && test_container "$mode"; then
            echo -e "${GREEN}✅ $mode mode test passed${NC}"
        else
            echo -e "${RED}❌ $mode mode test failed${NC}"
            success=false
        fi
        echo ""
    done
    
    if $success; then
        echo -e "${GREEN}🎉 All container tests passed!${NC}"
        echo ""
        echo -e "${BLUE}Running containers:${NC}"
        docker ps --filter name="${APP_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo -e "${BLUE}To stop all test containers:${NC} $0 stop"
        return 0
    else
        echo -e "${RED}❌ Some container tests failed${NC}"
        return 1
    fi
}

generate_compose() {
    local mode="$1"
    local compose_file="docker-compose.${mode}.generated.yml"
    
    echo -e "${BLUE}Generating $compose_file from centralized config...${NC}"
    
    if [ "$mode" = "dev" ]; then
        cat > "$compose_file" <<EOF
# Generated Docker Compose for Development
# =======================================
# Generated from app_config.nix - DO NOT EDIT MANUALLY
# Use: docker-manager.sh generate-compose dev
version: '3.8'

services:
  ${APP_NAME}-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
      args:
        DJANGO_MODULE: ${DJANGO_MODULE}
        DJANGO_PORT: ${SERVER_PORT}
        DJANGO_HOST: ${CONTAINER_HOST}
    ports:
      - "${SERVER_PORT}:${SERVER_PORT}"
    environment:
      DJANGO_SETTINGS_MODULE: ${DJANGO_MODULE}.settings_dev
      DJANGO_DEBUG: "true"
      DJANGO_HOST: ${CONTAINER_HOST}
      DJANGO_PORT: ${SERVER_PORT}
      PYTHONUNBUFFERED: 1
      WORKING_DIR: /app
      ENDO_API_MODE: development
      STORAGE_DIR: /app/data
      DJANGO_MODULE: ${DJANGO_MODULE}
    volumes:
      - ./data:/app/data
      - ./conf:/app/conf
      - ./data/logs:/app/logs
    command: ["sh", "-c", "devenv shell run-server-container"]
    networks:
      - ${APP_NAME}-network

networks:
  ${APP_NAME}-network:
    driver: bridge
EOF
    else
        cat > "$compose_file" <<EOF
# Generated Docker Compose for Production
# ======================================
# Generated from app_config.nix - DO NOT EDIT MANUALLY  
# Use: docker-manager.sh generate-compose prod
version: '3.8'

services:
  ${APP_NAME}:
    image: ${PROD_IMAGE}
    container_name: ${APP_NAME}-production
    restart: unless-stopped
    ports:
      - "${SERVER_PORT}:${SERVER_PORT}"
    environment:
      - ENDO_API_MODE=production
      - DJANGO_DEBUG=False
      - DJANGO_HOST=${CONTAINER_HOST}
      - DJANGO_PORT=${SERVER_PORT}
      - WORKING_DIR=/app
      - STORAGE_DIR=/app/data
      - DJANGO_MODULE=${DJANGO_MODULE}
      # Database connection
      - DATABASE_HOST=postgres
      - DATABASE_PORT=${POSTGRES_PORT}
      - DATABASE_NAME=${DB_NAME}
      - DATABASE_USER=${DB_USER}
      # Redis connection
      - REDIS_HOST=redis
      - REDIS_PORT=${REDIS_PORT}
    volumes:
      - ./data:/app/data:rw
      - ./conf:/app/conf:ro
      - ./data/logs:/app/logs:rw
    depends_on:
      - postgres
      - redis
    networks:
      - ${APP_NAME}-network

  postgres:
    image: postgres:${POSTGRES_VERSION}
    container_name: ${APP_NAME}-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${DB_NAME}
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./conf/init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    ports:
      - "${POSTGRES_PORT}:${POSTGRES_PORT}"
    networks:
      - ${APP_NAME}-network

  redis:
    image: redis:${REDIS_VERSION}
    container_name: ${APP_NAME}-redis
    restart: unless-stopped
    volumes:
      - redis_data:/data
    ports:
      - "${REDIS_PORT}:${REDIS_PORT}"
    networks:
      - ${APP_NAME}-network

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local

networks:
  ${APP_NAME}-network:
    driver: bridge

secrets:
  db_password:
    file: ./conf/db_pwd
EOF
    fi
    
    echo -e "${GREEN}✅ Generated $compose_file${NC}"
}

show_help() {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo "Container management commands:"
    echo "  build-dev        Build development container (DevEnv-based)"
    echo "  build-prod       Build production container (DevEnv-based)"
    echo "  build-all        Build both dev and prod containers"
    echo ""
    echo "Container lifecycle management:"
    echo "  run-dev          Create and run development container (removes existing)"
    echo "  run-prod         Create and run production container (removes existing)"  
    echo ""
    echo "  start-dev        Start existing development container"
    echo "  start-prod       Start existing production container"
    echo ""
    echo "  stop-dev         Stop development container (keep for restart)"
    echo "  stop-prod        Stop production container (keep for restart)"
    echo "  stop             Stop all containers (keep for restart)"
    echo ""
    echo "  remove-dev       Remove development container completely"
    echo "  remove-prod      Remove production container completely"  
    echo "  remove-all       Remove all containers completely"
    echo ""
    echo "  restart-dev      Stop and start development container"
    echo "  restart-prod     Stop and start production container"
    echo ""
    echo "  exec-dev         Execute command in development container"
    echo "  exec-prod        Execute command in production container"
    echo "  shell-dev        Open shell in development container"
    echo "  shell-prod       Open shell in production container"
    echo ""
    echo "  test-dev         Test development container"
    echo "  test-prod        Test production container"
    echo "  test-all         Run full container test suite"
    echo ""
    echo "  generate-compose-dev   Generate dev docker-compose.yml"
    echo "  generate-compose-prod  Generate prod docker-compose.yml"
    echo "  generate-compose-all   Generate both compose files"
    echo ""
    echo "  cleanup          Remove all container images"
    echo "  config           Show current configuration"
    echo "  help             Show this help message"
    echo ""
    echo "Features:"
    echo "  ✅ DevEnv-based containers with FFmpeg, OpenCV, CUDA support"
    echo "  ✅ Optimized multi-stage builds with aggressive caching"
    echo "  ✅ Git submodule integration"
    echo "  ✅ Fast startup times (DevEnv pre-built in container layers)"
    echo ""
    echo "Examples:"
    echo "  $0 run-dev       # Create and run development container"
    echo "  $0 stop-dev      # Stop development container (can restart later)"
    echo "  $0 start-dev     # Start stopped container or create if none exists"  
    echo "  $0 remove-dev    # Completely remove development container"
    echo "  $0 restart-dev   # Stop, remove, and create fresh container"
    echo "  $0 test-all      # Build and test both dev and prod containers"
}

main() {
    case "${1:-help}" in
        "build-dev")
            print_header
            print_config
            build_image "dev"
            ;;
        "build-prod")
            print_header
            print_config
            build_image "prod"
            ;;
        "build-all")
            print_header
            print_config
            build_image "dev"
            build_image "prod"
            ;;
        "run-dev")
            print_header
            print_config
            run_container "dev"
            ;;
        "run-prod")
            print_header
            print_config
            run_container "prod"
            ;;
        "test-dev")
            print_header
            print_config
            build_image "dev"
            run_container "dev"
            test_container "dev"
            ;;
        "test-prod")
            print_header
            print_config
            build_image "prod"
            run_container "prod" 
            test_container "prod"
            ;;
        "test-all")
            print_header
            print_config
            full_test
            ;;
        "generate-compose-dev")
            print_header
            generate_compose "dev"
            ;;
        "generate-compose-prod")
            print_header
            generate_compose "prod"
            ;;
        "generate-compose-all")
            print_header
            generate_compose "dev"
            generate_compose "prod"
            ;;
        "stop")
            print_header
            stop_containers
            ;;
        "stop-dev")
            print_header
            stop_containers "dev"
            ;;
        "stop-prod")
            print_header
            stop_containers "prod"
            ;;
        "remove-dev")
            print_header
            remove_containers "dev"
            ;;
        "remove-prod")
            print_header
            remove_containers "prod"
            ;;
        "remove-all")
            print_header
            remove_containers
            ;;
        "restart-dev")
            print_header
            print_config
            stop_containers "dev" "remove"
            run_container "dev"
            ;;
        "restart-prod")
            print_header
            print_config
            stop_containers "prod" "remove"
            run_container "prod"
            ;;
        "exec-dev")
            if [ $# -lt 1 ]; then
                echo -e "${RED}❌ Usage: $0 exec-dev <command>${NC}"
                exit 1
            fi
            shift  # Remove the command name
            exec_container "dev" "$@"
            ;;
        "exec-prod")
            if [ $# -lt 1 ]; then
                echo -e "${RED}❌ Usage: $0 exec-prod <command>${NC}"
                exit 1
            fi
            shift  # Remove the command name
            exec_container "prod" "$@"
            ;;
        "shell-dev")
            shell_container "dev"
            ;;
        "shell-prod")
            shell_container "prod"
            ;;
        "cleanup")
            print_header
            remove_containers
            cleanup_images
            ;;
        "config")
            print_header
            print_config
            ;;
        "start-dev")
            print_header
            print_config
            # Try to start existing container first, if that fails, run new one
            local container_name="${APP_NAME}-dev-test"
            if docker ps -aq -f name="$container_name" | grep -q .; then
                echo "Starting existing container..."
                if docker start "$container_name" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ Started existing $container_name${NC}"
                    echo "Container logs: docker logs -f $container_name"
                    echo "Stop container: docker stop $container_name"  
                    echo "Access: http://localhost:$SERVER_PORT"
                else
                    echo "Failed to start existing container, creating new one..."
                    run_container "dev"
                fi
            else
                echo "No existing container found, creating new one..."
                run_container "dev"
            fi
            ;;
        "start-prod")
            print_header
            print_config
            # Try to start existing container first, if that fails, run new one
            local container_name="${APP_NAME}-prod-test"
            if docker ps -aq -f name="$container_name" | grep -q .; then
                echo "Starting existing container..."
                if docker start "$container_name" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ Started existing $container_name${NC}"
                    echo "Container logs: docker logs -f $container_name"
                    echo "Stop container: docker stop $container_name"
                    echo "Access: http://localhost:$SERVER_PORT"
                else
                    echo "Failed to start existing container, creating new one..."
                    run_container "prod"
                fi
            else
                echo "No existing container found, creating new one..."
                run_container "prod"
            fi
            ;;
        "cleanup")
            print_header
            remove_containers
            cleanup_images
            ;;
        "config")
            print_header
            print_config
            ;;
        "help"|"--help"|"-h")
            print_header
            show_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Check dependencies
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

if ! command -v nix &> /dev/null; then
    echo -e "${RED}Error: Nix is not installed or not in PATH${NC}"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python3 is not installed or not in PATH${NC}"
    exit 1
fi

# Run main function
main "$@"
