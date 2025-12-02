using System.Net.WebSockets;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace RealtimeNotifications;

public class WebSocketEndpoint
{
    private readonly ConnectionManager _connectionManager;
    private readonly ILogger<WebSocketEndpoint> _logger;

    public WebSocketEndpoint(ConnectionManager connectionManager, ILogger<WebSocketEndpoint> logger)
    {
        _connectionManager = connectionManager;
        _logger = logger;
    }

    public async Task HandleAsync(HttpContext context)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("WebSocket request expected");
            return;
        }

        var userId = context.Request.Query["userId"].ToString();
        if (string.IsNullOrEmpty(userId))
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("UserId required");
            return;
        }

        using var webSocket = await context.WebSockets.AcceptWebSocketAsync();

        _logger.LogInformation("Client connected: {UserId}", userId);
        // Must await: stores userId-to-instanceId mapping in Redis for cross-instance routing
        await _connectionManager.RegisterConnection(userId, webSocket);

        var buffer = new byte[1024 * 4];
        try
        {
            while (webSocket.State == WebSocketState.Open)
            {
                var result = await webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);

                if (result.MessageType == WebSocketMessageType.Text && result.Count > 0)
                {
                    var text = System.Text.Encoding.UTF8.GetString(buffer, 0, result.Count);
                    _logger.LogInformation("WebSocket message from {UserId}: {Text}", userId, text);
                }

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    await webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "WebSocket error for {UserId}", userId);
        }
        finally
        {
            _logger.LogInformation("Client disconnected: {UserId}", userId);
            // Must await: removes userId-to-instanceId mapping from Redis when last connection closes
            await _connectionManager.UnregisterConnection(userId, webSocket);
        }
    }
}
