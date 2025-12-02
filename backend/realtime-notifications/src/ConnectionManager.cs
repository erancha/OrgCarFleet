using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;
using Newtonsoft.Json;

namespace RealtimeNotifications;

public class ConnectionManager
{
    private readonly ISubscriber _redisSubscriber;
    private readonly IConnectionMultiplexer _redis;
    private const string RedisChannelName = "ws-notifications";

    private readonly ILogger<ConnectionManager> _logger;

    // Maps each userId to their active WebSocket connections.
    // ConcurrentDictionary<WebSocket, byte> is used as a thread-safe set (no built-in ConcurrentHashSet in .NET).
    // The byte value is ignored; only the keys (WebSockets) matter.
    private readonly ConcurrentDictionary<string, ConcurrentDictionary<WebSocket, byte>> _userSockets = new();

    public ConnectionManager(IConnectionMultiplexer redis, ILogger<ConnectionManager> logger)
    {
        _redis = redis;
        _logger = logger;
        _redisSubscriber = redis.GetSubscriber();
        
        // Subscribe to Redis channel to handle horizontal scaling
        _redisSubscriber.Subscribe(RedisChannel.Literal(RedisChannelName), (channel, message) =>
        {
            HandleIncommingRedisMessage(message);
        });

        _logger.LogInformation("Subscribed to Redis channel {Channel}", RedisChannelName);
    }

    public void RegisterConnection(string userId, WebSocket socket)
    {
        var userConnections = _userSockets.GetOrAdd(userId, _ => new ConcurrentDictionary<WebSocket, byte>());
        userConnections.TryAdd(socket, 0);
    }

    public void UnregisterConnection(string userId, WebSocket socket)
    {
        if (_userSockets.TryGetValue(userId, out var userConnections))
        {
            userConnections.TryRemove(socket, out _);
            if (userConnections.IsEmpty)
            {
                _userSockets.TryRemove(userId, out _);
            }
        }
    }

    // Publish userId + payload to the Redis channel
    public async Task PublishToRedisChannel(string userId, object payload)
    {
        // Publish to Redis so ALL instances (including this one) check their connections
        var message = JsonConvert.SerializeObject(new { userId, payload });

        _logger.LogInformation(
            "Publishing notification for user {UserId} to Redis channel {Channel}: {Payload}",
            userId,
            RedisChannelName,
            message);

        await _redisSubscriber.PublishAsync(RedisChannel.Literal(RedisChannelName), message);
    }

    // Handle incomming message from the Redis channel
    private async void HandleIncommingRedisMessage(RedisValue message)
    {
        if (!message.HasValue) return;

        try
        {
            var raw = message.ToString();
            _logger.LogInformation("Received message from Redis channel {Channel}: {Message}", RedisChannelName, raw);

            var data = JsonConvert.DeserializeObject<dynamic>(raw);
            if (data == null) return;

            string? userId = data.userId;
            if (string.IsNullOrEmpty(userId)) return;

            var payload = data.payload;
            string jsonPayload = JsonConvert.SerializeObject(payload);
            var buffer = Encoding.UTF8.GetBytes(jsonPayload);

            if (_userSockets.TryGetValue(userId, out var userConnections))
            {
                _logger.LogInformation(
                    "Sending WebSocket notification to user {UserId} on {ConnectionCount} active connections",
                    userId,
                    userConnections.Count);

                foreach (var socket in userConnections.Keys)
                {
                    if (socket.State == WebSocketState.Open)
                    {
                        try 
                        {
                            await socket.SendAsync(
                                new ArraySegment<byte>(buffer),
                                WebSocketMessageType.Text,
                                true,
                                CancellationToken.None);
                        }
                        catch
                        {
                            // Socket likely dead, will be cleaned up by the connection handler
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling Redis message");
        }
    }
}
