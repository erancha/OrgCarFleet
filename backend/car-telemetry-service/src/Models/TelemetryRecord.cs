using NetTopologySuite.Geometries;

namespace CarTelemetryService.Models;

public class TelemetryRecord
{
    public long Id { get; set; }
    public string Type { get; set; } = string.Empty;
    public string? Action { get; set; }
    public string? VehicleId { get; set; }
    public string? Status { get; set; }
    public Point? Location { get; set; }
    public double? Speed { get; set; }
    public double? Heading { get; set; }
    public DateTime? EventTimestamp { get; set; }
    public string UserId { get; set; } = string.Empty;
    public string? UserEmail { get; set; }
    public string? RequestId { get; set; }
    public DateTime ReceivedAt { get; set; }
    public DateTime ProcessedAt { get; set; }
    public string? RawData { get; set; }
}
