using CarTelemetryService.Configuration;
using CarTelemetryService.Models;
using Microsoft.Extensions.Options;
using Npgsql;
using NetTopologySuite.Geometries;

namespace CarTelemetryService.Repositories;

public class PostGisRepository : IPostGisRepository
{
    private readonly PostgresSettings _settings;
    private readonly ILogger<PostGisRepository> _logger;

    public PostGisRepository(
        IOptions<PostgresSettings> settings,
        ILogger<PostGisRepository> logger)
    {
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task InitializeDatabaseAsync()
    {
        try
        {
            await using var connection = new NpgsqlConnection(_settings.GetConnectionString());
            await connection.OpenAsync();

            // Enable PostGIS extension
            await using var cmdExtension = new NpgsqlCommand(
                "CREATE EXTENSION IF NOT EXISTS postgis;",
                connection);
            await cmdExtension.ExecuteNonQueryAsync();

            // Create telemetry table with spatial index
            var createTableSql = @"
                CREATE TABLE IF NOT EXISTS car_telemetry (
                    id BIGSERIAL PRIMARY KEY,
                    type VARCHAR(50) NOT NULL,
                    action VARCHAR(100),
                    vehicle_id VARCHAR(100),
                    status VARCHAR(50),
                    location GEOGRAPHY(POINT, 4326),
                    speed DOUBLE PRECISION,
                    heading DOUBLE PRECISION,
                    event_timestamp TIMESTAMP WITH TIME ZONE,
                    user_id VARCHAR(100) NOT NULL,
                    user_email VARCHAR(255),
                    request_id VARCHAR(100),
                    received_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    processed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    raw_data JSONB,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );

                CREATE INDEX IF NOT EXISTS idx_car_telemetry_location 
                    ON car_telemetry USING GIST(location);
                
                CREATE INDEX IF NOT EXISTS idx_car_telemetry_type 
                    ON car_telemetry(type);
                
                CREATE INDEX IF NOT EXISTS idx_car_telemetry_vehicle_id 
                    ON car_telemetry(vehicle_id);
                
                CREATE INDEX IF NOT EXISTS idx_car_telemetry_action 
                    ON car_telemetry(action);
                
                CREATE INDEX IF NOT EXISTS idx_car_telemetry_status 
                    ON car_telemetry(status);
                
                CREATE INDEX IF NOT EXISTS idx_car_telemetry_event_timestamp 
                    ON car_telemetry(event_timestamp);
                
                CREATE INDEX IF NOT EXISTS idx_car_telemetry_processed_at 
                    ON car_telemetry(processed_at);
            ";

            await using var cmdTable = new NpgsqlCommand(createTableSql, connection);
            await cmdTable.ExecuteNonQueryAsync();

            _logger.LogInformation("Database initialized successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize database");
            throw;
        }
    }

    public async Task<long> InsertTelemetryAsync(TelemetryRecord record)
    {
        try
        {
            await using var connection = new NpgsqlConnection(_settings.GetConnectionString());
            await connection.OpenAsync();

            var sql = @"
                INSERT INTO car_telemetry (
                    type, action, vehicle_id, status, location, speed, heading,
                    event_timestamp, user_id, user_email, request_id,
                    received_at, processed_at, raw_data
                ) VALUES (
                    @type, @action, @vehicleId, @status,
                    ST_SetSRID(ST_MakePoint(@longitude, @latitude), 4326)::geography,
                    @speed, @heading, @eventTimestamp, @userId, @userEmail,
                    @requestId, @receivedAt, @processedAt, @rawData::jsonb
                ) RETURNING id;
            ";

            await using var cmd = new NpgsqlCommand(sql, connection);
            cmd.Parameters.AddWithValue("type", record.Type);
            cmd.Parameters.AddWithValue("action", (object?)record.Action ?? DBNull.Value);
            cmd.Parameters.AddWithValue("vehicleId", (object?)record.VehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("status", (object?)record.Status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("longitude", record.Location?.X ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("latitude", record.Location?.Y ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("speed", (object?)record.Speed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("heading", (object?)record.Heading ?? DBNull.Value);
            cmd.Parameters.AddWithValue("eventTimestamp", (object?)record.EventTimestamp ?? DBNull.Value);
            cmd.Parameters.AddWithValue("userId", record.UserId);
            cmd.Parameters.AddWithValue("userEmail", (object?)record.UserEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("requestId", (object?)record.RequestId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("receivedAt", record.ReceivedAt);
            cmd.Parameters.AddWithValue("processedAt", record.ProcessedAt);
            cmd.Parameters.AddWithValue("rawData", record.RawData ?? "{}");

            var id = await cmd.ExecuteScalarAsync();
            return Convert.ToInt64(id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to insert telemetry record");
            throw;
        }
    }
}
