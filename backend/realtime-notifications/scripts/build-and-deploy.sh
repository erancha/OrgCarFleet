#!/bin/bash

# Realtime Notifications Service Deployment Script
# This script builds and deploys the realtime notifications service using Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="orgcarfleet"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
AWS_CONFIG_FILE="${REPO_ROOT}/scripts/aws-config.sh"

if [ -f "${AWS_CONFIG_FILE}" ]; then
    set -a
    source "${AWS_CONFIG_FILE}"
    set +a
fi

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE_FILE="${SCRIPT_DIR}/.env.example"

if [ ! -f "${ENV_FILE}" ]; then
    if [ -f "${ENV_EXAMPLE_FILE}" ]; then
        cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
        print_warning "Created ${ENV_FILE} from ${ENV_EXAMPLE_FILE}."
        print_warning "Edit ${ENV_FILE} and set required values (e.g. REDIS_URL, KAFKA_BROKER_ENDPOINT), then re-run this script."
        exit 1
    fi

    print_error "Missing ${ENV_FILE}. Create it (you can copy from ${ENV_EXAMPLE_FILE}) and re-run."
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

echo "=========================================="
echo "Realtime Notifications Service Deployment"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}
 
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Parse command line arguments
COMMAND=${1:-up}

case $COMMAND in
    up)
        print_info "Starting services..."

        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" up -d
        print_info "Services started successfully!"
        print_info "Checking service status..."
        docker-compose -p "$PROJECT_NAME" ps
        ;;
    
    down)
        print_info "Stopping services..."
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" down
        print_info "Services stopped successfully!"
        ;;
    
    restart)
        print_info "Restarting services..."
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" restart
        print_info "Services restarted successfully!"
        ;;
    
    rebuild)
        print_info "Rebuilding and restarting services..."
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" down
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" build --no-cache
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" up -d
        print_info "Services rebuilt and started successfully!"
        ;;
    
    logs)
        SERVICE=${2:-realtime-notifications}
        print_info "Showing logs for $SERVICE..."
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" logs -f "$SERVICE"
        ;;
    
    status)
        print_info "Service status:"
        docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" ps
        ;;
    
    clean)
        print_warning "This will remove all containers, volumes, and images. Are you sure? (y/N)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            print_info "Cleaning up..."
            docker-compose -p "$PROJECT_NAME" -f "$DOCKER_COMPOSE_FILE" down -v --rmi all
            print_info "Cleanup complete!"
        else
            print_info "Cleanup cancelled."
        fi
        ;;
    
    *)
        echo "Usage: $0 {up|down|restart|rebuild|logs|status|clean}"
        echo ""
        echo "Commands:"
        echo "  up       - Start all services"
        echo "  down     - Stop all services"
        echo "  restart  - Restart all services"
        echo "  rebuild  - Rebuild and restart all services"
        echo "  logs     - Show logs (optional: specify service name)"
        echo "  status   - Show service status"
        echo "  clean    - Remove all containers, volumes, and images"
        exit 1
        ;;
esac

echo ""
print_info "Deployment script completed!"
