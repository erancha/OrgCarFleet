# OrgCarFleet

A car fleet management system built with AWS services, featuring event-driven architecture with Kafka and microservices for telemetry processing.

## Table of Contents

<!-- toc -->

- [Architecture](#architecture)
  - [Data Flow](#data-flow)
  - [Key Components](#key-components)
  - [Architecture Principles](#architecture-principles)
- [Services](#services)
  - [1. Ingestion Service](#1-ingestion-service)
  - [2. Car Telemetry Service](#2-car-telemetry-service)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
  - [Prerequisites](#prerequisites)
  - [Deploy All Services](#deploy-all-services)
  - [Deploy Individual Services](#deploy-individual-services)

<!-- tocstop -->

## Architecture

![Architecture Diagram](diagram-export-11-30-2025-7_34_53-PM.png)

### Data Flow

```
React Frontend → API Gateway + Cognito Auth → Ingestion Service (Lambda + SQS) →
Kafka → Car Telemetry Service (Kafka Consumer) → PostGIS Database
```

### Key Components

1. **Frontend** - React SPA with Google OIDC via Cognito
2. **API Gateway** - HTTP API with Cognito authorizer
3. **Ingestion Service** - Serverless event ingestion (Lambda + SQS + Kafka producer)
4. **Kafka Cluster** - Event streaming backbone (self-managed on AWS EC2)
5. **Car Telemetry Service** - .NET microservice consuming telemetry events
6. **PostGIS Database** - PostgreSQL with geospatial extensions for location data

### Architecture Principles

- **Serverless-first**: Low cost at low traffic, auto-scaling at high traffic
- **Event-driven**: Decoupled services via Kafka topics
- **Resilient**: SQS buffering, DLQ handling, automatic retries
- **Geospatial**: PostGIS for efficient location queries and spatial indexing

## Services

### 1. Ingestion Service

Serverless API for event ingestion with authentication.

- **Stack**: AWS Lambda, API Gateway, SQS, Cognito
- **Function**: Validates requests, authenticates users, queues events to Kafka
- **Topics**: `orgcarfleet-org-events`, `orgcarfleet-fleet-events`, `orgcarfleet-car-events`

📖 **[Ingestion Service Documentation](backend/ingestion-service/README.md)**

### 2. Car Telemetry Service

.NET microservice for processing vehicle telemetry data.

- **Stack**: .NET 8, Kafka Consumer, PostGIS, Docker
- **Function**: Consumes car events from Kafka, stores geospatial data in PostGIS
- **Features**: Real-time location tracking, spatial queries, telemetry analytics

📖 **[Car Telemetry Service Documentation](backend/car-telemetry-service/README.md)**

## Project Structure

```
OrgCarFleet/
├── backend/
│   ├── ingestion-service/          # Serverless event ingestion
│   └── car-telemetry-service/      # Kafka consumer microservice
├── frontend/                       # React SPA
│   ├── src/                        # React components
│   └── package.json
├── scripts/                        # Global deployment scripts
│   ├── build-deploy.sh             # Main orchestrator
│   ├── aws-config.sh               # AWS credentials
│   └── cognito-config.sh           # Cognito setup
└── README.md                       # This file
```

## Quick Start

### Prerequisites

- Node.js 20+ and npm
- .NET 8.0 SDK
- Docker and Docker Compose
- AWS CLI configured
- Kafka cluster (AWS EC2)
- PostgreSQL with PostGIS (AWS EC2)

### Deploy All Services

```bash
cd scripts
./build-deploy.sh dev
```

### Deploy Individual Services

**Ingestion Service:**

```bash
cd backend/ingestion-service/scripts
./build-deploy.sh dev
```

**Car Telemetry Service:**

```bash
cd backend/car-telemetry-service/scripts
./build-deploy.sh up
```

**Frontend:**

```bash
cd frontend
npm install
npm start
```
