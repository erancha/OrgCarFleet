namespace CarTelemetryService.Configuration;

public class KafkaSettings
{
    public string BootstrapServers { get; set; } = string.Empty;
    public string GroupId { get; set; } = "car-telemetry-consumer-group";
    public List<string> Topics { get; set; } = new();
    public string AutoOffsetReset { get; set; } = "earliest";
    public bool EnableAutoCommit { get; set; } = false;
}
