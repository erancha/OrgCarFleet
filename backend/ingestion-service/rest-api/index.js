const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');

const sqsClient = new SQSClient({ region: process.env.AWS_REGION });
const queueUrl = process.env.SQS_QUEUE_URL;

/**
 * Lambda handler for API Gateway requests
 * Validates authenticated user and sends message to SQS
 */
exports.handler = async (event) => {
  // console.log('Received event:', JSON.stringify(event, null, 2));

  try {
    // Extract user info from Cognito authorizer
    const userId = event.requestContext?.authorizer?.claims?.sub;
    const userEmail = event.requestContext?.authorizer?.claims?.email;

    if (!userId) {
      return {
        statusCode: 401,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ error: 'Unauthorized - No user ID found' }),
      };
    }

    // Parse request body
    let requestBody;
    try {
      requestBody = JSON.parse(event.body || '{}');
    } catch (parseError) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ error: 'Invalid JSON in request body' }),
      };
    }

    // Create message for SQS
    const message = {
      userId,
      userEmail,
      timestamp: new Date().toISOString(),
      requestData: requestBody,
      requestId: event.requestContext.requestId,
    };

    // Send message to SQS
    const command = new SendMessageCommand({
      QueueUrl: queueUrl,
      MessageBody: JSON.stringify(message),
      MessageAttributes: {
        userId: {
          DataType: 'String',
          StringValue: userId,
        },
        userEmail: {
          DataType: 'String',
          StringValue: userEmail || 'unknown',
        },
      },
    });

    const result = await sqsClient.send(command);

    console.log('Message sent to SQS:', result.MessageId);

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        success: true,
        messageId: result.MessageId,
        message: 'Request queued successfully',
        userId,
        userEmail,
      }),
    };
  } catch (error) {
    console.error('Error processing request:', error);

    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        error: 'Internal server error',
        message: error.message,
      }),
    };
  }
};
