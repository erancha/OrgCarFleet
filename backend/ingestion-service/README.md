# Ingestion Service

A serverless event ingestion service built with AWS Lambda, API Gateway, SQS, and Kafka for high-scale fleet management event processing.

<!-- toc -->

- [Architecture](#architecture)
  * [Data Flow](#data-flow)
  * [Components](#components)
  * [Architecture Rationale](#architecture-rationale)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Development](#development)
- [Deployment](#deployment)
- [Monitoring & Observability](#monitoring--observability)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

<!-- tocstop -->

## Architecture

This hybrid serverless architecture is designed for **high-scale ingestion** with low initial cost and the ability to scale efficiently.

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

## Project Structure

```
ingestion-service/
├── rest-api/
│   ├── index.js           # REST API Lambda handler (API Gateway → SQS)
│   └── package.json       # Lambda dependencies
├── sqs-to-kafka/
│   ├── index.js           # Batch producer Lambda handler (SQS → Kafka)
│   └── package.json       # Lambda dependencies (kafkajs)
└── scripts/
    ├── template.yaml      # CloudFormation/SAM template
    └── build-deploy.sh    # Deployment script
```

## Prerequisites

- Node.js 20+ and npm
- AWS CLI configured with appropriate credentials
- AWS SAM CLI installed
- Existing Cognito User Pool with Google OAuth configured
- Kafka cluster accessible from Lambda (AWS EC2)

## Configuration

**Environment Variables** (configured in `template.yaml`):

_REST API Lambda:_

- `SQS_QUEUE_URL` - SQS queue URL for event buffering

_Batch Producer Lambda:_

- `KAFKA_BROKERS` - Kafka broker endpoints (comma-separated)
- `KAFKA_USERNAME` - Kafka SASL username (from Secrets Manager)
- `KAFKA_PASSWORD` - Kafka SASL password (from Secrets Manager)

**Kafka Topics:**

Events are routed based on the `type` field:

- `type: "org"` → `orgcarfleet-org-events`
- `type: "fleet"` → `orgcarfleet-fleet-events`
- `type: "car"` → `orgcarfleet-car-events`

## Development

**Testing:**

```bash
# Single request
curl -X POST https://YOUR_API_ID.execute-api.REGION.amazonaws.com/dev/api \
  -H "Authorization: YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type": "car", "action": "status-update", "vehicleId": "CAR-001", "status": "available"}'

# Load testing (1000 requests, 100 concurrent)
cd ../../scripts
./load-test.sh https://YOUR_API_URL YOUR_ID_TOKEN
```

**Debugging:**

```bash
# CloudWatch Logs
aws logs tail /aws/lambda/orgcarfleet-rest-api-dev --follow
aws logs tail /aws/lambda/orgcarfleet-sqs-to-kafka-dev --follow

# SQS Queue
aws sqs get-queue-attributes \
  --queue-url https://sqs.REGION.amazonaws.com/ACCOUNT_ID/orgcarfleet-events-queue \
  --attribute-names All

# Kafka Topics
kafka-topics --list --bootstrap-server ec2-3-71-113-150.eu-central-1.compute.amazonaws.com:19092
```

## Deployment

**Option A: Deploy via main orchestrator (recommended):**

```bash
cd ../../scripts
./build-deploy.sh dev
```

**Option B: Deploy ingestion service only:**

```bash
cd scripts
chmod +x build-deploy.sh
./build-deploy.sh dev
```

## Monitoring & Observability

**CloudWatch Metrics:**

_API Gateway:_ `Count`, `4XXError`, `5XXError`, `Latency`  
_REST API Lambda:_ `Invocations`, `Errors`, `Duration`, `Throttles`  
_SQS Queue:_ `ApproximateNumberOfMessagesVisible`, `ApproximateAgeOfOldestMessage`  
_Batch Producer Lambda:_ `Invocations`, `Errors`, `Duration`, `IteratorAge`

**CloudWatch Logs:**

- `/aws/lambda/orgcarfleet-rest-api-{stage}`
- `/aws/lambda/orgcarfleet-sqs-to-kafka-{stage}`

**Recommended Alarms:**

- High SQS Queue Depth: `ApproximateNumberOfMessagesVisible > 10000`
- Old Messages: `ApproximateAgeOfOldestMessage > 300` seconds
- Lambda Errors: `Errors > 10` in 5 minutes
- Lambda Throttles: `Throttles > 0`
- API Gateway 5XX: `5XXError > 1%` of requests

## Security

- Cognito Authorizer validates JWT tokens from Cognito User Pool
- Kafka credentials stored in AWS Secrets Manager
- IAM roles follow least-privilege principle
- Lambda functions can be deployed in VPC for private Kafka access
- TLS/SSL encryption for all Kafka connections

## Troubleshooting

**"Unauthorized" Error:**

- Ensure Cognito ID token is valid and not expired
- Check Cognito App Client ID matches authorizer configuration
- Verify token is in `Authorization` header

**"Failed to send request" Error:**

- Check API Gateway URL is correct
- Verify Lambda has `sqs:SendMessage` permission
- Check CloudWatch Logs for Lambda errors

**Messages Not Reaching Kafka:**

- Check batch producer Lambda CloudWatch Logs for Kafka connection errors
- Verify Kafka broker endpoints are correct and accessible
- Ensure Kafka credentials in Secrets Manager are valid
- Check Lambda VPC configuration if Kafka is in private subnet
- Verify security groups allow outbound traffic to Kafka port (19092)

**High SQS Queue Depth:**

- Check batch producer Lambda for errors or throttling
- Verify Kafka cluster is healthy
- Increase Lambda reserved concurrency if needed
- Check SQS event source mapping configuration

**Lambda Cold Starts:**

- Consider enabling Provisioned Concurrency for batch producer Lambda
- Optimize Lambda package size
- Use Lambda layers for shared dependencies
