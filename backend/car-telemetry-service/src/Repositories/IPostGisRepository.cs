using CarTelemetryService.Models;

namespace CarTelemetryService.Repositories;

public interface IPostGisRepository
{
    Task InitializeDatabaseAsync();
    Task<long> InsertTelemetryAsync(TelemetryRecord record);
}
