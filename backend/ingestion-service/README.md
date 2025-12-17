# Ingestion Service

A serverless event ingestion service built with AWS Lambda, API Gateway, SQS, and Kafka for high-scale fleet management event processing.

<!-- toc -->

- [Architecture](#architecture)
  * [Data Flow](#data-flow)
  * [Components](#components)
  * [Architecture Rationale](#architecture-rationale)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)

<!-- tocstop -->

## Architecture

This hybrid serverless architecture is designed for **high-scale ingestion** with low initial cost

### Data Flow

```
API Gateway (HTTP API + Cognito Auth) → REST API Lambda → SQS Queue →
→ Batch Producer Lambda → Kafka Topics
```

### Components

1. **API Gateway (HTTP API)** - Handles incoming HTTP requests with Cognito authorization
2. **REST API Lambda** - Validates and authenticates requests, pushes events to SQS
3. **SQS Queue** - Durable message buffer for asynchronous processing and decoupling
4. **Batch Producer Lambda** - Reads from SQS in batches and produces to Kafka topics
5. **Kafka Cluster** - High-throughput message streaming (self-managed on AWS EC2)

### Architecture Rationale

- **Low initial cost**: Pay-per-invocation Lambda (no baseline infrastructure cost at low traffic)
- **Efficient batching**: SQS event source mapping batches up to 10,000 records/6 MB per Lambda invocation
- **Connection reuse**: Kafka producer initialized in Lambda global scope, reused across warm invocations
- **Decoupled & resilient**: SQS buffer protects against Kafka downtime; built-in retries and DLQ
- **Auto-scaling**: Lambda concurrency scales with SQS backlog
- **Future-proof**: Route MQTT (AWS IoT Core) to same SQS queue without changing downstream components

## Prerequisites

- Node.js 20+ and npm
- AWS CLI configured with appropriate credentials
- AWS SAM CLI installed
- Existing Cognito User Pool with Google OIDC configured
- Kafka cluster accessible from Lambda (AWS EC2)

## Deployment

```bash
./scripts/build-and-deploy.sh dev # (chmod +x build-and-deploy.sh)
```

**Testing:**

```bash
# Single request
curl -X POST https://YOUR_API_ID.execute-api.REGION.amazonaws.com/dev/api \
  -H "Authorization: YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type": "car", "action": "status-update", "vehicleId": "CAR-001", "status": "available"}'
```
