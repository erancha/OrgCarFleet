using Confluent.Kafka;
using Confluent.Kafka.Admin;
using Microsoft.Extensions.Options;
using Newtonsoft.Json;
using RealtimeNotifications.Configuration;

namespace RealtimeNotifications;

public class KafkaConsumerService : IHostedService, IDisposable
{
    private readonly KafkaSettings _settings;
    private readonly ConnectionManager _connectionManager;
    private readonly ILogger<KafkaConsumerService> _logger;

    private CancellationTokenSource? _cts;
    private Task? _consumerTask;

    public KafkaConsumerService(
        IOptions<KafkaSettings> settings,
        ConnectionManager connectionManager,
        ILogger<KafkaConsumerService> logger)
    {
        _settings = settings.Value;
        _connectionManager = connectionManager;
        _logger = logger;
    }

    // Starts the Kafka consumer service in a background task
    public Task StartAsync(CancellationToken cancellationToken)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _consumerTask = Task.Run(() => RunConsumerLoopAsync(_cts.Token), _cts.Token);
        return Task.CompletedTask;
    }

    // Stops the Kafka consumer service and waits for the background task to complete
    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_cts != null)
        {
            _cts.Cancel();
        }

        if (_consumerTask != null)
        {
            await Task.WhenAny(_consumerTask, Task.Delay(Timeout.Infinite, cancellationToken));
        }
    }

    // Disposes of the cancellation token source
    public void Dispose()
    {
        _cts?.Dispose();
    }

    // Checks if Kafka topics exist and creates them with 2 partitions if missing
    private async Task EnsureTopicsExistAsync(string bootstrapServers, List<string> topics, CancellationToken cancellationToken)
    {
        var adminConfig = new AdminClientConfig
        {
            BootstrapServers = bootstrapServers
        };

        using var adminClient = new AdminClientBuilder(adminConfig).Build();

        try
        {
            var metadata = adminClient.GetMetadata(TimeSpan.FromSeconds(10));
            var existingTopics = metadata.Topics.Select(t => t.Topic).ToHashSet();

            var missingTopics = topics.Where(t => !existingTopics.Contains(t)).ToList();

            if (missingTopics.Any())
            {
                _logger.LogWarning("Topics do not exist and will be created with 2 partitions: {Topics}", 
                    string.Join(", ", missingTopics));

                var topicSpecifications = missingTopics.Select(topic => new TopicSpecification
                {
                    Name = topic,
                    NumPartitions = 2,
                    ReplicationFactor = 1
                }).ToList();

                await adminClient.CreateTopicsAsync(topicSpecifications);
                
                _logger.LogInformation("Successfully created topics: {Topics}", string.Join(", ", missingTopics));
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error ensuring topics exist. Topics: {Topics}", string.Join(", ", topics));
            throw;
        }
    }

    // Runs the main Kafka consumer loop to process messages and route them to connected users
    private async Task RunConsumerLoopAsync(CancellationToken stoppingToken)
    {
        var config = new ConsumerConfig
        {
            BootstrapServers = _settings.BootstrapServers,
            GroupId = _settings.GroupId,
            AutoOffsetReset = Enum.Parse<AutoOffsetReset>(_settings.AutoOffsetReset, true),
            EnableAutoCommit = _settings.EnableAutoCommit
        };

        using var consumer = new ConsumerBuilder<string, string>(config).Build();
        
        try
        {
            await EnsureTopicsExistAsync(_settings.BootstrapServers, _settings.Topics, stoppingToken);
            
            consumer.Subscribe(_settings.Topics);
            _logger.LogInformation("Subscribed to topics: {Topics}", string.Join(", ", _settings.Topics));

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var consumeResult = consumer.Consume(TimeSpan.FromMilliseconds(100));
                    
                    if (consumeResult == null) continue;
                    if (consumeResult.Message == null) continue;

                    string? messageValue = consumeResult.Message.Value;
                    string? messageKey = consumeResult.Message.Key;

                    if (string.IsNullOrEmpty(messageValue)) continue;

                    _logger.LogInformation($"Received Kafka message. Key: {messageKey}, Value: {messageValue}");

                    // Parse message to extract userId
                    // Expecting structure from previous services
                    dynamic? messageData = JsonConvert.DeserializeObject(messageValue);
                    
                    if (messageData != null)
                    {
                        // Try to find UserId in various places based on the ecosystem conventions
                        string? userId = messageKey 
                                     ?? (string?)messageData.userId 
                                     ?? (string?)messageData.restMetadata?.userId;

                        if (!string.IsNullOrEmpty(userId))
                        {
                            await _connectionManager.SendToUser(userId, messageData);
                        }
                    }
                }
                catch (ConsumeException e)
                {
                    _logger.LogError($"Kafka error: {e.Error.Reason}");
                }
                catch (Exception e)
                {
                    _logger.LogError($"Error processing message: {e.Message}");
                    await Task.Delay(1000, stoppingToken);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown
        }
        finally
        {
            consumer.Close();
        }
    }
}
