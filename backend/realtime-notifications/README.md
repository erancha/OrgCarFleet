# Realtime Notifications Service

This service is responsible for delivering real-time notifications to the frontend using WebSockets. It consumes events from a Kafka topic and routes them to connected users.

## Architecture

- **.NET 8**: Runtime environment (ASP.NET Core Web API).
- **WebSocket**: Native ASP.NET Core WebSocket middleware for real-time connections.
- **Kafka (Confluent.Kafka)**: Consumes events from the `orgcarfleet-notifications` topic.
- **Redis (StackExchange.Redis)**: Used for horizontal scalability (Pub/Sub) to broadcast events across instances.

## Configuration

The service is configured via `appsettings.json` and environment variables:

- **Port**: Configured in `launchSettings.json` (`applicationUrl`) for local development, or via environment in Docker/K8s (default: 8080).
- **Kafka**: Configured via the `Kafka` section in `appsettings.json` using the Options pattern:
  - `Kafka__BootstrapServers`: Kafka broker address
  - `Kafka__GroupId`: Consumer group ID
  - `Kafka__Topics`: Array of topics to consume
  - `Kafka__AutoOffsetReset`: Offset reset behavior
  - `Kafka__EnableAutoCommit`: Auto-commit setting
- **Redis**: Configured via `REDIS_URL` (connection string with host, port, and password)

## Scalability

This service is horizontally scalable. It uses Redis Pub/Sub to broadcast Kafka events to all running instances. Each instance then checks its local WebSocket connections and delivers the message to the target user if connected.

## Deployment

### Docker Compose

To run the service and its dependencies (Redis) locally:

```bash
docker-compose up --build
```

### Usage

Connect to the WebSocket endpoint:

```
ws://host:8080/?userId=123
```
