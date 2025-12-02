using Confluent.Kafka;
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

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _consumerTask = Task.Run(() => RunConsumerLoopAsync(_cts.Token), _cts.Token);
        return Task.CompletedTask;
    }

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

    public void Dispose()
    {
        _cts?.Dispose();
    }

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
