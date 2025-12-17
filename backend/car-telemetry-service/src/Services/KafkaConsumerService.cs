using Confluent.Kafka;
using CarTelemetryService.Configuration;
using CarTelemetryService.Models;
using CarTelemetryService.Repositories;
using Microsoft.Extensions.Options;
using Newtonsoft.Json;
using NetTopologySuite.Geometries;

namespace CarTelemetryService.Services;

public class KafkaConsumerService : BackgroundService
{
    private readonly KafkaSettings _kafkaSettings;
    private readonly IPostGisRepository _repository;
    private readonly ILogger<KafkaConsumerService> _logger;
    private IConsumer<string, string>? _consumer;

    public KafkaConsumerService(
        IOptions<KafkaSettings> kafkaSettings,
        IPostGisRepository repository,
        ILogger<KafkaConsumerService> logger)
    {
        _kafkaSettings = kafkaSettings.Value;
        _repository = repository;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Kafka Consumer Service starting...");

        // Initialize database
        await _repository.InitializeDatabaseAsync();

        var config = new ConsumerConfig
        {
            BootstrapServers = _kafkaSettings.BootstrapServers,
            GroupId = _kafkaSettings.GroupId,
            AutoOffsetReset = Enum.Parse<AutoOffsetReset>(_kafkaSettings.AutoOffsetReset, true),
            EnableAutoCommit = _kafkaSettings.EnableAutoCommit,
            EnableAutoOffsetStore = false,
            SessionTimeoutMs = 30000,
            MaxPollIntervalMs = 300000,
        };

        _consumer = new ConsumerBuilder<string, string>(config)
            .SetErrorHandler((_, e) => _logger.LogError("Kafka error: {Reason}", e.Reason))
            .Build();

        // Validate topics configuration
        if (_kafkaSettings.Topics == null || _kafkaSettings.Topics.Count == 0)
        {
            _logger.LogError("No Kafka topics configured. Topics list is empty or null.");
            throw new InvalidOperationException("Kafka topics configuration is missing or empty. Please configure Kafka:Topics in appsettings.json or environment variables.");
        }

        _logger.LogInformation("Attempting to subscribe to {Count} topic(s): {Topics}", 
            _kafkaSettings.Topics.Count, 
            string.Join(", ", _kafkaSettings.Topics));

        _consumer.Subscribe(_kafkaSettings.Topics);
        _logger.LogInformation("Successfully subscribed to topics: {Topics}", string.Join(", ", _kafkaSettings.Topics));

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var consumeResult = _consumer.Consume(stoppingToken);

                    if (consumeResult?.Message == null)
                        continue;

                    await ProcessMessageAsync(consumeResult, stoppingToken);

                    // Manually commit offset after successful processing
                    _consumer.StoreOffset(consumeResult);
                    _consumer.Commit(consumeResult);
                }
                catch (ConsumeException ex)
                {
                    _logger.LogError(ex, "Error consuming message: {Error}", ex.Error.Reason);
                }
                catch (OperationCanceledException)
                {
                    _logger.LogInformation("Consumer operation cancelled");
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Unexpected error processing message");
                    await Task.Delay(1000, stoppingToken); // Brief delay before retry
                }
            }
        }
        finally
        {
            _consumer?.Close();
            _consumer?.Dispose();
            _logger.LogInformation("Kafka Consumer Service stopped");
        }
    }

    private async Task ProcessMessageAsync(ConsumeResult<string, string> consumeResult, CancellationToken cancellationToken)
    {
        var message = consumeResult.Message;
        
        _logger.LogInformation(
            "Consumed message from topic: {Topic}, Partition: {Partition}, Offset: {Offset}, Key: {Key}",
            consumeResult.Topic,
            consumeResult.Partition.Value,
            consumeResult.Offset.Value,
            message.Key);

        try
        {
            // Parse the Kafka message
            var telemetryMessage = JsonConvert.DeserializeObject<TelemetryMessage>(message.Value);
            
            if (telemetryMessage == null)
            {
                _logger.LogWarning("Failed to deserialize message: {Value}", message.Value);
                return;
            }

            // Log the consumed message
            _logger.LogInformation(
                "Processing telemetry - Type: {Type}, Action: {Action}, VehicleId: {VehicleId}, Status: {Status}, UserId: {UserId}, RequestId: {RequestId}",
                telemetryMessage.ClientData?.Type,
                telemetryMessage.ClientData?.Action,
                telemetryMessage.ClientData?.VehicleId,
                telemetryMessage.ClientData?.Status,
                telemetryMessage.RestMetadata?.UserId,
                telemetryMessage.RestMetadata?.RequestId);

            // Convert to database record
            var record = MapToTelemetryRecord(telemetryMessage, message.Value);

            // Insert into PostGIS
            var id = await _repository.InsertTelemetryAsync(record);

            _logger.LogInformation(
                "Successfully stored telemetry record with ID: {Id} for VehicleId: {VehicleId}",
                id,
                record.VehicleId);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to parse JSON message: {Value}", message.Value);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process and store message");
            throw; // Re-throw to prevent offset commit
        }
    }

    private TelemetryRecord MapToTelemetryRecord(TelemetryMessage message, string rawJson)
    {
        var clientData = message.ClientData;
        var restMetadata = message.RestMetadata;

        Point? location = null;
        if (clientData?.Location != null)
        {
            location = new Point(clientData.Location.Lng, clientData.Location.Lat) 
            { 
                SRID = 4326 
            };
        }

        DateTime? eventTimestamp = null;
        if (!string.IsNullOrEmpty(clientData?.Timestamp))
        {
            if (DateTime.TryParse(clientData.Timestamp, out var parsedTimestamp))
            {
                eventTimestamp = parsedTimestamp;
            }
        }

        DateTime receivedAt = DateTime.UtcNow;
        if (!string.IsNullOrEmpty(restMetadata?.ReceivedAt))
        {
            if (DateTime.TryParse(restMetadata.ReceivedAt, out var parsedReceivedAt))
            {
                receivedAt = parsedReceivedAt;
            }
        }

        return new TelemetryRecord
        {
            Type = clientData?.Type ?? "unknown",
            Action = clientData?.Action,
            VehicleId = clientData?.VehicleId,
            Status = clientData?.Status,
            Location = location,
            Speed = clientData?.Speed,
            Heading = clientData?.Heading,
            EventTimestamp = eventTimestamp,
            UserId = restMetadata?.UserId ?? "unknown",
            UserEmail = restMetadata?.UserEmail,
            RequestId = restMetadata?.RequestId,
            ReceivedAt = receivedAt,
            ProcessedAt = DateTime.UtcNow,
            RawData = rawJson
        };
    }

    public override void Dispose()
    {
        _consumer?.Dispose();
        base.Dispose();
    }
}
