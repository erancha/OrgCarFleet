# Car Telemetry Service

A .NET Core microservice that consumes telemetry data from Kafka topics and stores it in PostGIS for geospatial analysis.

<!-- toc -->

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Development](#development)
- [Deployment](#deployment)

<!-- tocstop -->

## Architecture

- **Kafka Consumer**: Subscribes to `orgcarfleet-car-events` topics
- **PostGIS Storage**: Stores telemetry data with geospatial indexing
- **Dependency Injection**: Clean architecture with DI container

## Prerequisites

- .NET 8.0 SDK (for local development)
- Docker and Docker Compose (for deployment)

## Development

Update `appsettings*.json` with your local Kafka and PostgreSQL settings.

```bash
cd src
dotnet restore
dotnet run
```

## Deployment

**Using deployment script:**

```bash
./scripts/build-and-deploy.sh <command>
```

Available commands:

- `up` - Start all services
- `down` - Stop all services
- `restart` - Restart all services
- `rebuild` - Rebuild and restart all services
- `logs [service]` - Show logs
- `status` - Show service status
- `clean` - Remove all containers, volumes, and images
