import React, { useState, useEffect, useRef } from 'react';
import { config } from './config';
import WebSocketNotifications from './WebSocketNotifications';
import './App.css';

// Manual OIDC helper functions
const generateCodeVerifier = () => {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return btoa(String.fromCharCode(...array))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
};

const generateCodeChallenge = async (verifier) => {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return btoa(String.fromCharCode(...new Uint8Array(hash)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
};

const generateState = () => {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return btoa(String.fromCharCode(...array))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
};

function App() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [requestData, setRequestData] = useState('{"type": "car", "action": "status-update", "vehicleId": "CAR-001", "status": "available"}');
  const [requestCount, setRequestCount] = useState(1);
  const [response, setResponse] = useState(null);
  const [error, setError] = useState(null);
  const [sending, setSending] = useState(false);
  const authProcessed = useRef(false);

  useEffect(() => {
    // Prevent double execution in React Strict Mode
    if (!authProcessed.current) {
      authProcessed.current = true;
      checkUser();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const checkUser = async () => {
    try {
      const urlParams = new URLSearchParams(window.location.search);
      const code = urlParams.get('code');
      const state = urlParams.get('state');

      if (code && state) {
        const savedState = sessionStorage.getItem('oidc_state');
        const codeVerifier = sessionStorage.getItem('code_verifier');

        // Only process if we have the matching state and verifier
        if (savedState && codeVerifier && state === savedState) {
          console.log('Processing OIDC callback...');

          // Exchange code for tokens
          const tokenUrl = `https://${config.cognitoDomain}/oauth2/token`;
          const body = new URLSearchParams({
            grant_type: 'authorization_code',
            client_id: config.clientId,
            code: code,
            redirect_uri: config.redirectUri,
            code_verifier: codeVerifier,
          });

          const response = await fetch(tokenUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: body.toString(),
          });

          const tokens = await response.json();

          if (!response.ok) {
            console.error('Token exchange error:', tokens);
            throw new Error(tokens.error_description || tokens.error || 'Token exchange failed');
          }

          // console.log('✅ Tokens received:', tokens);

          // Store tokens
          localStorage.setItem('id_token', tokens.id_token);
          localStorage.setItem('access_token', tokens.access_token);
          localStorage.setItem('refresh_token', tokens.refresh_token);

          // Decode ID token to get user info
          const payload = JSON.parse(atob(tokens.id_token.split('.')[1]));
          setUser({ email: payload.email, sub: payload.sub, name: payload.name });

          // Clean up
          sessionStorage.removeItem('oidc_state');
          sessionStorage.removeItem('code_verifier');
        }

        // Always clean up the URL
        window.history.replaceState({}, document.title, window.location.pathname);
      }

      // Check if already authenticated (runs if no code, or after code processing)
      if (!user) {
        const idToken = localStorage.getItem('id_token');
        if (idToken) {
          try {
            const payload = JSON.parse(atob(idToken.split('.')[1]));
            // Check if token is expired
            if (payload.exp * 1000 > Date.now()) {
              setUser({ email: payload.email, sub: payload.sub, name: payload.name });
            } else {
              console.log('Token expired, clearing...');
              localStorage.clear();
            }
          } catch (e) {
            console.error('Invalid token:', e);
            localStorage.clear();
          }
        }
      }
    } catch (err) {
      console.error('Auth error:', err);
      setError(err.message);
      localStorage.clear();
      sessionStorage.clear();
      window.history.replaceState({}, document.title, window.location.pathname);
    } finally {
      setLoading(false);
    }
  };

  const handleSignIn = async () => {
    try {
      const state = generateState();
      const codeVerifier = generateCodeVerifier();
      const codeChallenge = await generateCodeChallenge(codeVerifier);

      sessionStorage.setItem('oidc_state', state);
      sessionStorage.setItem('code_verifier', codeVerifier);

      const authUrl =
        `https://${config.cognitoDomain}/oauth2/authorize?` +
        `response_type=code&` +
        `client_id=${config.clientId}&` +
        `redirect_uri=${encodeURIComponent(config.redirectUri)}&` +
        `state=${state}&` +
        `scope=openid+email+profile+phone&` +
        `code_challenge=${codeChallenge}&` +
        `code_challenge_method=S256&` +
        `identity_provider=Google`;

      window.location.href = authUrl;
    } catch (err) {
      console.error('Error signing in:', err);
      setError(`Failed to sign in: ${err.message}`);
    }
  };

  const handleSignOut = () => {
    localStorage.clear();
    sessionStorage.clear();
    setUser(null);
    setResponse(null);
    setError(null);
  };

  const sendRequest = async () => {
    if (!requestData.trim()) {
      setError('Please enter some data to send');
      return;
    }

    setSending(true);
    setError(null);
    setResponse(null);

    try {
      const idToken = localStorage.getItem('id_token');

      if (!idToken) {
        throw new Error('No authentication token found');
      }

      // Parse request data as JSON if possible
      let bodyData;
      try {
        bodyData = JSON.parse(requestData);
      } catch {
        bodyData = { message: requestData };
      }

      // Send multiple requests
      const count = Math.min(Math.max(1, requestCount), 1000); // Clamp between 1 and 1000
      const results = [];
      const errors = [];

      for (let i = 0; i < count; i++) {
        try {
          const response = await fetch(`${config.apiUrl}/api`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: idToken,
            },
            body: JSON.stringify(bodyData),
          });

          const data = await response.json();

          if (!response.ok) {
            errors.push({ requestNumber: i + 1, error: data.error || 'Request failed' });
          } else {
            results.push({ requestNumber: i + 1, ...data });
          }
        } catch (err) {
          errors.push({ requestNumber: i + 1, error: err.message });
        }
      }

      // Set response with summary
      setResponse({
        totalRequests: count,
        successful: results.length,
        failed: errors.length,
        results: count === 1 ? results[0] : results.slice(0, 5), // Show first 5 if multiple
        errors: errors.length > 0 ? errors.slice(0, 5) : undefined, // Show first 5 errors if any
      });
      setRequestData('');
    } catch (err) {
      console.error('Error sending request:', err);
      setError(err.message || 'Failed to send request');
    } finally {
      setSending(false);
    }
  };

  if (loading) {
    return (
      <div className='app'>
        <div className='card'>
          <div className='loading'>Loading...</div>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className='app'>
        <div className='card'>
          <h1>🚗 OrgCarFleet</h1>
          <p className='subtitle'>Fleet Management System</p>
          <button onClick={handleSignIn} className='btn btn-primary'>
            Sign in with Google
          </button>
          {error && <div className='error'>{error}</div>}
        </div>
      </div>
    );
  }

  return (
    <div className='app'>
      <div className='card'>
        <div className='header'>
          <div>
            <h1>🚗 OrgCarFleet</h1>
            <p className='user-info'>Signed in as: {user.email || user.name || user.sub}</p>
          </div>
          <button onClick={handleSignOut} className='btn btn-secondary'>
            Sign Out
          </button>
        </div>

        <div className='content'>
          <h2>Send Request to API</h2>
          <textarea
            value={requestData}
            onChange={(e) => setRequestData(e.target.value)}
            placeholder='Enter JSON data, e.g., {"type": "car", "action": "test", "data": "hello"}'
            rows={6}
            className='textarea'
          />
          <div style={{ marginBottom: '1rem' }}>
            <label htmlFor='requestCount' style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 'bold' }}>
              Number of Requests:
            </label>
            <select
              id='requestCount'
              value={requestCount}
              onChange={(e) => setRequestCount(parseInt(e.target.value))}
              style={{ padding: '0.5rem', width: '150px', fontSize: '1rem' }}
            >
              <option value='1'>1</option>
              <option value='10'>10</option>
              <option value='100'>100</option>
              <option value='1000'>1000</option>
            </select>
          </div>
          <button onClick={sendRequest} disabled={sending || !requestData.trim()} className='btn btn-primary'>
            {sending ? `Sending ${requestCount} request${requestCount > 1 ? 's' : ''}...` : `Send ${requestCount} Request${requestCount > 1 ? 's' : ''}`}
          </button>

          {error && (
            <div className='error'>
              <strong>Error:</strong> {error}
            </div>
          )}

          {response && (
            <div className='success'>
              <h3>✓ Success</h3>
              <pre>{JSON.stringify(response, null, 2)}</pre>
            </div>
          )}

          <WebSocketNotifications userId={user.sub} />
        </div>
      </div>
    </div>
  );
}

export default App;
