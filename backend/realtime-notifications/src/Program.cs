using Microsoft.Extensions.Options;
using RealtimeNotifications;
using RealtimeNotifications.Configuration;
using StackExchange.Redis;

var builder = WebApplication.CreateBuilder(args);

// Basic startup diagnostics
Console.WriteLine("--------------------------------------------------");
Console.WriteLine($"Environment: {builder.Environment.EnvironmentName}");
Console.WriteLine($"Redis URL: {builder.Configuration["REDIS_URL"]}");
Console.WriteLine($"Kafka BootstrapServers: {builder.Configuration["Kafka:BootstrapServers"]}");
Console.WriteLine($"Kafka GroupId: {builder.Configuration["Kafka:GroupId"]}");
Console.WriteLine("--------------------------------------------------");

// Configuration
var redisUrl = builder.Configuration["REDIS_URL"] ?? "localhost:6379";

// Bind Kafka Settings
builder.Services.Configure<KafkaSettings>(builder.Configuration.GetSection("Kafka"));

// Services
var redisOptions = ConfigurationOptions.Parse(redisUrl);
redisOptions.AbortOnConnectFail = false;
builder.Services.AddSingleton<IConnectionMultiplexer>(ConnectionMultiplexer.Connect(redisOptions));

// Register services for horizontal scaling
// Each service instance (container/pod) has one ConnectionManager
// Multiple instances are deployed via Docker/K8s for true horizontal scaling
builder.Services.AddSingleton<ConnectionManager>();
builder.Services.AddHostedService<KafkaConsumerService>();
builder.Services.AddScoped<WebSocketEndpoint>();

var app = builder.Build();

// Enable WebSockets
app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromMinutes(2)
});

// Map WebSocket endpoint
app.Map("/ws", (WebSocketEndpoint endpoint, HttpContext context) => endpoint.HandleAsync(context));

// Simple health endpoint
app.MapGet("/", () => "Realtime Notifications Service Running");

Console.WriteLine("Starting Realtime Notifications service (WebSocket endpoint at /ws) ...");

app.Run();
