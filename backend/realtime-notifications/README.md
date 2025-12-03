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

This service is horizontally scalable. When a Kafka event arrives, the service first checks if the target user is connected locally. If yes, it delivers the message directly via WebSocket. If not, it uses Redis to look up which instance has the user and publishes the message to that specific instance's Redis channel.

[Diagram](https://miro.com/app/live-embed/uXjVJhUeMrw=/?embedMode=view_only_without_ui&moveToViewport=-1823%2C-2410%2C4011%2C2654&embedId=333513776545)

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
