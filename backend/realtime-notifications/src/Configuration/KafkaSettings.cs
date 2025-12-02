namespace RealtimeNotifications.Configuration;

public class KafkaSettings
{
    public required string BootstrapServers { get; set; }
    public required string GroupId { get; set; }
    public required List<string> Topics { get; set; }
    public required string AutoOffsetReset { get; set; }
    public bool EnableAutoCommit { get; set; }
}
