# Car Telemetry Service

A .NET Core microservice that consumes telemetry data from Kafka topics and stores it in PostGIS for geospatial analysis.

<!-- toc -->

- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  * [External Infrastructure](#external-infrastructure)
- [Database Schema](#database-schema)
- [Development](#development)
  * [Local Development](#local-development)
  * [Build Docker Image](#build-docker-image)
- [Deployment](#deployment)
- [Testing](#testing)
- [Monitoring](#monitoring)

<!-- tocstop -->

## Architecture

- **Kafka Consumer**: Subscribes to `orgcarfleet-{org|fleet|car}-events` topics from external Kafka broker
- **PostGIS Storage**: Stores telemetry data with geospatial indexing on external PostgreSQL server
- **Dependency Injection**: Clean architecture with DI container
- **Docker Compose**: Lightweight deployment connecting to external AWS EC2 infrastructure

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

## Features

1. **Kafka Integration**

   - Consumes from multiple topics: `orgcarfleet-org-events`, `orgcarfleet-fleet-events`, `orgcarfleet-car-events`
   - Manual offset management for reliable processing
   - Automatic reconnection and error handling

2. **PostGIS Storage**

   - Automatic database and table initialization
   - Geospatial indexing for location queries
   - Stores raw JSON for full message preservation
   - Tracks processing timestamps

3. **Logging**
   - Structured logging with configurable levels
   - Message processing tracking
   - Error logging with context

## Prerequisites

- .NET 8.0 SDK (for local development)
- Docker and Docker Compose (for deployment)
- Access to external Kafka broker (AWS EC2)
- Access to external PostgreSQL/PostGIS server (AWS EC2)

## Configuration

Create a `.env` file based on the template. Configuration priority (highest to lowest):

1. Environment variables
2. `.env` file
3. `appsettings.{Environment}.json`
4. `appsettings.json`

### External Infrastructure

**Kafka Broker (AWS EC2)**

**PostgreSQL/PostGIS (AWS EC2)**

## Database Schema

The service creates a `car_telemetry` table with the following structure:

```sql
CREATE TABLE car_telemetry (
    id BIGSERIAL PRIMARY KEY,
    type VARCHAR(50) NOT NULL,
    org_id VARCHAR(100),
    fleet_id VARCHAR(100),
    car_id VARCHAR(100),
    location GEOGRAPHY(POINT, 4326),  -- PostGIS geospatial type
    speed DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    event_timestamp TIMESTAMP WITH TIME ZONE,
    user_id VARCHAR(100) NOT NULL,
    user_email VARCHAR(255),
    request_id VARCHAR(100),
    received_at TIMESTAMP WITH TIME ZONE NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    raw_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
```

Indexes:

- Spatial index on `location` (GIST)
- B-tree indexes on `type`, `car_id`, `event_timestamp`, `processed_at`

## Development

### Local Development

```bash
cd src
dotnet restore
dotnet run
```

Update `appsettings.Development.json` with your local Kafka and PostgreSQL settings.

### Build Docker Image

```bash
cd src
docker build -t car-telemetry-service .
```

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

**Using docker-compose directly:**

```bash
docker-compose up -d                              # Start
docker-compose logs -f car-telemetry-service      # Logs
docker-compose down                               # Stop
```

## Testing

**Send test messages:**

```bash
./scripts/test-kafka-producer.sh orgcarfleet-car-events
./scripts/test-kafka-producer.sh orgcarfleet-fleet-events
```

**Query data:**

```bash
psql -h ec2-63-180-181-179.eu-central-1.compute.amazonaws.com -U postgres -d orgcarfleet_db
```

```sql
-- Recent telemetry
SELECT id, type, car_id, ST_AsText(location::geometry) as location,
       speed, event_timestamp, processed_at
FROM car_telemetry
ORDER BY processed_at DESC
LIMIT 10;

-- Geospatial query (cars within 10km)
SELECT car_id, speed, ST_Distance(location, ST_MakePoint(34.7818, 32.0853)::geography) as distance_meters
FROM car_telemetry
WHERE ST_DWithin(location, ST_MakePoint(34.7818, 32.0853)::geography, 10000)
ORDER BY distance_meters;
```

## Monitoring

**View Service Logs:**

```bash
docker-compose logs -f car-telemetry-service
```

**View Kafka Topics:**

```bash
# Requires Kafka CLI tools installed locally or on the Kafka server
kafka-topics --list --bootstrap-server ec2-3-71-113-150.eu-central-1.compute.amazonaws.com:19092
```

**View Consumer Groups:**

```bash
kafka-consumer-groups \
    --bootstrap-server ec2-3-71-113-150.eu-central-1.compute.amazonaws.com:19092 \
    --describe \
    --group car-telemetry-consumer-group
```
