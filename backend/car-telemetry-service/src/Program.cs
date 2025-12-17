using CarTelemetryService.Services;
using CarTelemetryService.Repositories;
using CarTelemetryService.Configuration;

var builder = Host.CreateApplicationBuilder(args);

// Configure settings
builder.Services.Configure<KafkaSettings>(
    builder.Configuration.GetSection("Kafka"));
builder.Services.Configure<PostgresSettings>(
    builder.Configuration.GetSection("Postgres"));

// Register services
builder.Services.AddSingleton<IPostGisRepository, PostGisRepository>();
builder.Services.AddHostedService<KafkaConsumerService>();

// Configure logging
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.SetMinimumLevel(LogLevel.Information);

var host = builder.Build();
host.Run();
