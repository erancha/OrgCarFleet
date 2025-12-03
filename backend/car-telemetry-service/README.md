# Car Telemetry Service

A .NET Core microservice that consumes telemetry data from Kafka topics and stores it in PostGIS for geospatial analysis.

<!-- toc -->

- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Development](#development)
  * [Local Development](#local-development)
- [Deployment](#deployment)

<!-- tocstop -->

## Architecture

- **Kafka Consumer**: Subscribes to `orgcarfleet-car-events` topics
- **PostGIS Storage**: Stores telemetry data with geospatial indexing
- **Dependency Injection**: Clean architecture with DI container

## Project Structure

```
car-telemetry-service/
├── src/                          # Source code
│   ├── Configuration/            # Settings classes
│   ├── Models/                   # Data models
│   ├── Repositories/             # Data access layer
│   ├── Services/                 # Business logic
│   ├── Program.cs                # Application entry point
│   ├── appsettings.json          # Configuration
│   └── Dockerfile                # Container definition
├── scripts/                      # Deployment and utility scripts
│   ├── build-deploy.sh           # Deployment script
│   └── test-kafka-producer.sh    # Test message producer
├── docker-compose.yml            # Multi-container orchestration
└── README.md                     # This file
```

## Prerequisites

- .NET 8.0 SDK (for local development)
- Docker and Docker Compose (for deployment)

## Configuration

Create a `.env` file based on the template. Configuration priority (highest to lowest):

1. Environment variables
2. `.env` file
3. `appsettings.{Environment}.json`
4. `appsettings.json`

## Development

### Local Development

```bash
cd src
dotnet restore
dotnet run
```

Update `appsettings.Development.json` with your local Kafka and PostgreSQL settings.

## Deployment

**Using deployment script:**

```bash
./scripts/build-deploy.sh <command>
```

Available commands:

- `up` - Start all services
- `down` - Stop all services
- `restart` - Restart all services
- `rebuild` - Rebuild and restart all services
- `logs [service]` - Show logs
- `status` - Show service status
- `clean` - Remove all containers, volumes, and images
