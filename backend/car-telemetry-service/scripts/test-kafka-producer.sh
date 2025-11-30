#!/bin/bash

# Test script to produce sample messages to Kafka topics
# This helps verify the car telemetry service is consuming correctly

set -e

KAFKA_BROKER=${KAFKA_BROKER:-localhost:9092}
TOPIC=${1:-orgcarfleet-car-events}

echo "=========================================="
echo "Kafka Test Producer"
echo "=========================================="
echo "Broker: $KAFKA_BROKER"
echo "Topic: $TOPIC"
echo ""

# Sample telemetry message matching the format from sqs-to-kafka service
MESSAGE='{
  "clientData": {
    "type": "car",
    "action": "status-update",
    "vehicleId": "CAR-001",
    "status": "available",
    "location": {
      "lat": 40.7128,
      "lng": -74.006
    },
    "speed": 65.5,
    "heading": 180.0,
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'",
    "data": {
      "fuelLevel": 75,
      "engineTemp": 90,
      "batteryVoltage": 12.6
    }
  },
  "restMetadata": {
    "userId": "13a4f8d2-40c1-709a-4fab-ad3485adf968",
    "userEmail": "erancha@gmail.com",
    "requestId": "'$(uuidgen)'",
    "receivedAt": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'"
  },
  "sentToSQS": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'",
  "producedToKafka": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'"
}'

echo "Sending test message to topic: $TOPIC"
echo ""
echo "$MESSAGE" | docker exec -i orgcarfleet-kafka kafka-console-producer \
    --broker-list localhost:29092 \
    --topic "$TOPIC" \
    --property "parse.key=true" \
    --property "key.separator=:"

echo ""
echo "Message sent successfully!"
echo ""
echo "To verify, check the car-telemetry-service logs:"
echo "  docker-compose logs -f car-telemetry-service"
