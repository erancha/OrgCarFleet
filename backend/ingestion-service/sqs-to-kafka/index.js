const { Kafka } = require('kafkajs');

// Initialize Kafka client
const kafka = new Kafka({
  clientId: 'orgcarfleet-batch-producer',
  brokers: [process.env.KAFKA_BROKER_ENDPOINT],
  retry: {
    initialRetryTime: 100,
    retries: 8,
  },
});

const producer = kafka.producer();
let producerConnected = false;

/**
 * Lambda handler for SQS to Kafka batch processing
 * Reads messages from SQS in batches and produces to Kafka topics
 */
exports.handler = async (event) => {
  console.log('Received SQS event with', event.Records.length, 'messages');

  try {
    // Connect producer if not already connected
    if (!producerConnected) {
      await producer.connect();
      producerConnected = true;
      console.log('Kafka producer connected');
    }

    // Process messages in batch - group by type for topic routing
    const messagesByType = {
      org: [],
      fleet: [],
      car: [],
    };
    const processedMessages = [];
    const failedMessageIds = [];

    for (const record of event.Records) {
      try {
        const messageBody = JSON.parse(record.body);
        const requestData = messageBody.requestData || {};
        const type = requestData.type; // Extract type: 'org', 'fleet', or 'car'

        // Validate type
        if (!type || !['org', 'fleet', 'car'].includes(type)) {
          console.error('Invalid or missing type in message:', record.messageId, 'type:', type);
          failedMessageIds.push(record.messageId);
          continue; // Skip invalid messages - will be redelivered and eventually moved to DLQ
        }

        console.log('Processing message:', {
          messageId: record.messageId,
          userId: messageBody.userId,
          type: type,
          timestamp: messageBody.timestamp,
        });

        // Prepare Kafka message with clear field organization
        const kafkaMessage = {
          key: messageBody.userId, // Partition by userId for ordering
          value: JSON.stringify({
            // Client-provided data (from original HTTP request body)
            clientData: requestData,

            // REST API metadata (added by REST Lambda)
            restMetadata: {
              userId: messageBody.userId,
              userEmail: messageBody.userEmail,
              requestId: messageBody.requestId,
              receivedAt: messageBody.timestamp, // When REST API received the request
            },

            // SQS metadata (added by SQS service)
            // sqsMetadata: {
            //   messageId: record.messageId,
            sentToSQS: new Date(parseInt(record.attributes.SentTimestamp)).toISOString(), // When SQS received the message
            // },

            // Processing metadata (added by this Lambda)
            // processingMetadata: {
            producedToKafka: new Date().toISOString(), // When this Lambda processed the message
            // source: 'sqs-to-kafka-lambda',
            // },
          }),
          headers: {
            source: 'sqs-batch-producer',
            userId: messageBody.userId,
            requestId: messageBody.requestId || '',
            type: type,
          },
        };

        // Route to appropriate topic based on type
        messagesByType[type].push(kafkaMessage);

        processedMessages.push({
          messageId: record.messageId,
          userId: messageBody.userId,
          type: type,
        });
      } catch (parseError) {
        console.error('Error parsing message:', record.messageId, parseError);
        failedMessageIds.push(record.messageId);
        // Continue processing other messages
      }
    }

    // Send batches to Kafka - one batch per topic/type
    const sendPromises = [];
    for (const [type, messages] of Object.entries(messagesByType)) {
      if (messages.length > 0) {
        const topic = `orgcarfleet-${type}-events`;
        sendPromises.push(
          producer
            .send({
              topic: topic,
              messages: messages,
              compression: 1, // GZIP compression
            })
            .then((result) => ({
              topic,
              messageCount: messages.length,
              result,
            }))
        );
      }
    }

    // Wait for all sends to complete
    if (sendPromises.length > 0) {
      const results = await Promise.all(sendPromises);
      console.log(
        'Successfully sent batches to Kafka:',
        JSON.stringify(
          results.map((r) => ({
            topic: r.topic,
            messageCount: r.messageCount,
            topicPartitions: r.result,
          })),
          null,
          2
        )
      );
    }

    // Report invalid messages as failures so SQS will redeliver them
    // After maxReceiveCount (3) attempts, SQS automatically moves them to DLQ
    return {
      batchItemFailures: failedMessageIds.map((messageId) => ({
        itemIdentifier: messageId,
      })),
    };
  } catch (error) {
    console.error('Error processing batch:', error);

    // Return all message IDs as failures for retry
    return {
      batchItemFailures: event.Records.map((record) => ({
        itemIdentifier: record.messageId,
      })),
    };
  }
};

// Graceful shutdown handler
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, disconnecting Kafka producer');
  if (producerConnected) {
    await producer.disconnect();
    producerConnected = false;
  }
});
