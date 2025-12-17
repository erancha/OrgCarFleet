using Newtonsoft.Json;

namespace CarTelemetryService.Models;

public class TelemetryMessage
{
    [JsonProperty("clientData")]
    public ClientData? ClientData { get; set; }

    [JsonProperty("restMetadata")]
    public RestMetadata? RestMetadata { get; set; }

    [JsonProperty("sentToSQS")]
    public string? SentToSQS { get; set; }

    [JsonProperty("producedToKafka")]
    public string? ProducedToKafka { get; set; }
}

public class ClientData
{
    [JsonProperty("type")]
    public string Type { get; set; } = string.Empty;

    [JsonProperty("action")]
    public string? Action { get; set; }

    [JsonProperty("vehicleId")]
    public string? VehicleId { get; set; }

    [JsonProperty("status")]
    public string? Status { get; set; }

    [JsonProperty("location")]
    public LocationData? Location { get; set; }

    [JsonProperty("speed")]
    public double? Speed { get; set; }

    [JsonProperty("heading")]
    public double? Heading { get; set; }

    [JsonProperty("timestamp")]
    public string? Timestamp { get; set; }

    [JsonProperty("data")]
    public Dictionary<string, object>? Data { get; set; }
}

public class LocationData
{
    [JsonProperty("lat")]
    public double Lat { get; set; }

    [JsonProperty("lng")]
    public double Lng { get; set; }
}

public class RestMetadata
{
    [JsonProperty("userId")]
    public string UserId { get; set; } = string.Empty;

    [JsonProperty("userEmail")]
    public string? UserEmail { get; set; }

    [JsonProperty("requestId")]
    public string? RequestId { get; set; }

    [JsonProperty("receivedAt")]
    public string? ReceivedAt { get; set; }
}
