import React, { useState, useEffect, useRef, useCallback } from 'react';

const WebSocketNotifications = ({ userId }) => {
  const [notifications, setNotifications] = useState([]);
  const [isConnected, setIsConnected] = useState(false);
  const ws = useRef(null);
  const retryCount = useRef(0);
  const reconnectTimeout = useRef(null);

  const connect = useCallback(() => {
    if (!userId) return;

    // Clean up any existing connection
    if (ws.current && ws.current.readyState === WebSocket.OPEN) {
      return; // Already connected
    }

    // In a real environment, this URL should come from config
    const wsUrl = `ws://localhost:8080/ws?userId=${userId}`;
    ws.current = new WebSocket(wsUrl);

    ws.current.onopen = () => {
      console.log('WebSocket Connected');
      setIsConnected(true);
      retryCount.current = 0;
    };

    ws.current.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        console.log('Received notification:', message);
        setNotifications((prev) => [message, ...prev].slice(0, 50)); // Keep last 50
      } catch (e) {
        console.error('Error parsing websocket message', e);
      }
    };

    ws.current.onclose = () => {
      console.log('WebSocket Disconnected');
      setIsConnected(false);

      // Exponential backoff for reconnection
      const timeout = Math.min(1000 * Math.pow(2, retryCount.current), 30000);
      retryCount.current += 1;

      reconnectTimeout.current = setTimeout(() => {
        connect();
      }, timeout);
    };

    ws.current.onerror = (error) => {
      console.error('WebSocket Error:', error);
      // onclose will be called after onerror, so reconnection is handled there
    };
  }, [userId]);

  useEffect(() => {
    connect();

    return () => {
      // Clear any pending reconnect timeout
      if (reconnectTimeout.current) {
        clearTimeout(reconnectTimeout.current);
      }
      // Close the WebSocket connection
      if (ws.current) {
        ws.current.close();
      }
    };
  }, [connect]);

  return (
    <div className='notifications-panel' style={{ marginTop: '20px', padding: '15px', border: '1px solid #ddd', borderRadius: '8px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
        <h3>Live Notifications</h3>
        <span
          style={{
            padding: '4px 8px',
            borderRadius: '4px',
            backgroundColor: isConnected ? '#d4edda' : '#f8d7da',
            color: isConnected ? '#155724' : '#721c24',
            fontSize: '0.8rem',
          }}
        >
          {isConnected ? 'Connected' : 'Disconnected'}
        </span>
      </div>

      <div className='notifications-list' style={{ maxHeight: '200px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {notifications.length === 0 ? (
          <p style={{ color: '#666', fontStyle: 'italic' }}>No notifications yet...</p>
        ) : (
          notifications.map((notif, index) => (
            <div key={index} style={{ padding: '8px', backgroundColor: '#f8f9fa', borderRadius: '4px', borderLeft: '3px solid #007bff' }}>
              <div style={{ fontSize: '0.8rem', color: '#666' }}>{new Date().toLocaleTimeString()}</div>
              <div>{JSON.stringify(notif)}</div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};

export default WebSocketNotifications;
