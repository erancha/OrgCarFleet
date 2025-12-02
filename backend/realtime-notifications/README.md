# Realtime Notifications Service

This service is responsible for delivering real-time notifications to the frontend using WebSockets. It consumes events from a Kafka topic and routes them to connected users.

## Architecture

- **.NET 8**: Runtime environment (ASP.NET Core Web API).
- **WebSocket**: Native ASP.NET Core WebSocket middleware for real-time connections.
- **Kafka (Confluent.Kafka)**: Consumes events from the `orgcarfleet-notifications` topic.
- **Redis (StackExchange.Redis)**: Used for horizontal scalability (Pub/Sub) to broadcast events across instances.

## Configuration

The service is configured via environment variables:

- `PORT`: The port to run the WebSocket server on (default: 8080).
- `KAFKA_BROKER_ENDPOINT`: The Kafka broker address.
- `REDIS_URL`: The Redis connection string.

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
