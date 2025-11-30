#!/bin/bash

# Car Telemetry Service Deployment Script
# This script builds and deploys the car telemetry service using Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="orgcarfleet"

echo "=========================================="
echo "Car Telemetry Service Deployment"
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

# Navigate to project root
cd "$PROJECT_ROOT"

# Parse command line arguments
COMMAND=${1:-up}

case $COMMAND in
    up)
        print_info "Starting services..."
        
        # Check if .env file exists, if not copy from .env.example
        if [ ! -f "$PROJECT_ROOT/.env" ]; then
            if [ -f "$PROJECT_ROOT/.env.example" ]; then
                print_warning ".env file not found. Creating from .env.example..."
                cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
                print_warning "Please review and update .env file with your actual credentials!"
            else
                print_error ".env.example file not found. Please create .env file manually."
                exit 1
            fi
        fi
        
        docker-compose -p "$PROJECT_NAME" up -d
        print_info "Services started successfully!"
        print_info "Checking service status..."
        docker-compose -p "$PROJECT_NAME" ps
        ;;
    
    down)
        print_info "Stopping services..."
        docker-compose -p "$PROJECT_NAME" down
        print_info "Services stopped successfully!"
        ;;
    
    restart)
        print_info "Restarting services..."
        docker-compose -p "$PROJECT_NAME" restart
        print_info "Services restarted successfully!"
        ;;
    
    rebuild)
        print_info "Rebuilding and restarting services..."
        docker-compose -p "$PROJECT_NAME" down
        docker-compose -p "$PROJECT_NAME" build --no-cache
        docker-compose -p "$PROJECT_NAME" up -d
        print_info "Services rebuilt and started successfully!"
        ;;
    
    logs)
        SERVICE=${2:-car-telemetry-service}
        print_info "Showing logs for $SERVICE..."
        docker-compose -p "$PROJECT_NAME" logs -f "$SERVICE"
        ;;
    
    status)
        print_info "Service status:"
        docker-compose -p "$PROJECT_NAME" ps
        ;;
    
    clean)
        print_warning "This will remove all containers, volumes, and images. Are you sure? (y/N)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            print_info "Cleaning up..."
            docker-compose -p "$PROJECT_NAME" down -v --rmi all
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
