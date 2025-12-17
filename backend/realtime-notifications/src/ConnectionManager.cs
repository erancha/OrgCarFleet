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
    private readonly IDatabase _redisDb;
    private const string RedisChannelPrefix = "ws-notifications:";
    private const string UserInstanceMappingHash = "user-instance-mapping";
    
    private readonly string _instanceId;
    private readonly ILogger<ConnectionManager> _logger;

    // Maps each userId to their active WebSocket connections.
    // ConcurrentDictionary<WebSocket, byte> is used as a thread-safe set (no built-in ConcurrentHashSet in .NET).
    // The byte value is ignored; only the keys (WebSockets) matter.
    private readonly ConcurrentDictionary<string, ConcurrentDictionary<WebSocket, byte>> _localUserSocketsMapping = new();

    public ConnectionManager(IConnectionMultiplexer redis, ILogger<ConnectionManager> logger)
    {
        _redis = redis;
        _logger = logger;
        _redisSubscriber = redis.GetSubscriber();
        _redisDb = redis.GetDatabase();
        
        // Generate unique instance ID for this ConnectionManager
        _instanceId = Guid.NewGuid().ToString();
        
        // Subscribe to this instance's specific Redis channel
        var instanceChannel = RedisChannelPrefix + _instanceId;
        _redisSubscriber.Subscribe(RedisChannel.Literal(instanceChannel), (channel, message) =>
        {
            HandleIncommingRedisMessage(message);
        });

        _logger.LogInformation("ConnectionManager instance {InstanceId} subscribed to Redis channel {Channel}", _instanceId, instanceChannel);
    }

    public async Task RegisterConnection(string userId, WebSocket socket)
    {
        var userConnections = _localUserSocketsMapping.GetOrAdd(userId, _ => new ConcurrentDictionary<WebSocket, byte>());
        userConnections.TryAdd(socket, 0);
        
        // Store mapping from userId to this instance ID in Redis hash (HSET)
        // More memory-efficient than individual keys, atomic updates
        await _redisDb.HashSetAsync(UserInstanceMappingHash, userId, _instanceId);
        
        _logger.LogInformation("Registered connection for user {UserId} on instance {InstanceId}", userId, _instanceId);
    }

    public async Task UnregisterConnection(string userId, WebSocket socket)
    {
        if (_localUserSocketsMapping.TryGetValue(userId, out var userConnections))
        {
            userConnections.TryRemove(socket, out _);
            if (userConnections.IsEmpty)
            {
                _localUserSocketsMapping.TryRemove(userId, out _);
                
                // Remove mapping from Redis hash when no more connections for this user (HDEL)
                await _redisDb.HashDeleteAsync(UserInstanceMappingHash, userId);
                
                _logger.LogInformation("Unregistered last connection for user {UserId} on instance {InstanceId}", userId, _instanceId);
            }
        }
    }

    // Send message to a specific user - checks local connections first, then routes via Redis
    public async Task SendToUser(string userId, object payload)
    {
        // Check if user is connected locally
        if (_localUserSocketsMapping.TryGetValue(userId, out var userConnections) && !userConnections.IsEmpty)
        {
            _logger.LogInformation(
                "User {UserId} found locally on instance {InstanceId}, sending directly to {ConnectionCount} connections",
                userId,
                _instanceId,
                userConnections.Count);
            
            await SendToLocalConnections(userId, payload, userConnections);
        }
        else
        {
            // User not connected locally, check Redis hash for the instance that has this user (HGET)
            var targetInstanceId = await _redisDb.HashGetAsync(UserInstanceMappingHash, userId);
            
            if (targetInstanceId.HasValue)
            {
                var targetInstance = targetInstanceId.ToString();
                _logger.LogInformation(
                    "User {UserId} not local, routing to instance {TargetInstanceId}",
                    userId,
                    targetInstance);
                
                // Publish to the specific instance's channel
                await PublishToInstanceChannel(targetInstance, userId, payload);
            }
            else
            {
                _logger.LogWarning(
                    "User {UserId} not found in any instance (no Redis hash mapping)",
                    userId);
            }
        }
    }
    
    // Publish to a specific instance's Redis channel
    private async Task PublishToInstanceChannel(string targetInstanceId, string userId, object payload)
    {
        var message = JsonConvert.SerializeObject(new { userId, payload });
        var instanceChannel = RedisChannelPrefix + targetInstanceId;

        _logger.LogInformation(
            "Publishing notification for user {UserId} to instance channel {Channel}",
            userId,
            instanceChannel);

        await _redisSubscriber.PublishAsync(RedisChannel.Literal(instanceChannel), message);
    }

    // Handle incoming message from this instance's Redis channel
    private async void HandleIncommingRedisMessage(RedisValue message)
    {
        if (!message.HasValue) return;

        try
        {
            var raw = message.ToString();
            var instanceChannel = RedisChannelPrefix + _instanceId;
            _logger.LogInformation("Instance {InstanceId} received message from Redis channel {Channel}: {Message}", 
                _instanceId, instanceChannel, raw);

            var data = JsonConvert.DeserializeObject<dynamic>(raw);
            if (data == null) return;

            string? userId = data.userId;
            if (string.IsNullOrEmpty(userId)) return;

            var payload = data.payload;

            if (_localUserSocketsMapping.TryGetValue(userId, out var userConnections))
            {
                await SendToLocalConnections(userId, payload, userConnections);
            }
            else
            {
                _logger.LogWarning(
                    "Instance {InstanceId} received message for user {UserId} but user not connected locally",
                    _instanceId,
                    userId);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling Redis message on instance {InstanceId}", _instanceId);
        }
    }
    
    // Send payload to local WebSocket connections
    private async Task SendToLocalConnections(string userId, object payload, ConcurrentDictionary<WebSocket, byte> userConnections)
    {
        string jsonPayload = JsonConvert.SerializeObject(payload);
        var buffer = Encoding.UTF8.GetBytes(jsonPayload);
        
        // _logger.LogInformation(
        //     "Sending WebSocket notification to user {UserId} on instance {InstanceId} to {ConnectionCount} active connections",
        //     userId,
        //     _instanceId,
        //     userConnections.Count);

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
