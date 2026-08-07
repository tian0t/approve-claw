#!/usr/bin/env node

// Minimal relay server: forwards opaque payloads between peers via WebSocket.
// - Accepts device WS connections (query: ?device=<id>&token=...)
// - Accepts HTTP POST /forward { to, payload }
// - Never persists payloads to disk; only forwards in-memory

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.RELAY_PORT || process.env.PORT || 4000);

const clients = new Map(); // deviceId -> ws

function logMeta(msg, meta = {}) {
  const safe = { ...meta };
  // Avoid logging payload contents
  if (safe.payload) delete safe.payload;
  console.log(`[relay] ${msg}`, JSON.stringify(safe));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'POST' && req.url === '/forward') {
    try {
      let body = '';
      for await (const chunk of req) body += chunk;
      const obj = JSON.parse(body || '{}');
      const { to, payload, ttl } = obj;
      if (!to || !payload) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'missing to or payload' }));
        return;
      }

      logMeta('forward requested', { to, ttl });

      const ws = clients.get(String(to));
      if (!ws || ws.readyState !== ws.OPEN) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'recipient offline' }));
        return;
      }

      // Forward opaque payload - do not interpret or log
      ws.send(JSON.stringify({ type: 'relay', payload }));

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'forwarded' }));
    } catch (e) {
      console.error('[relay] forward error', e && e.message);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'internal' }));
    }
    return;
  }

  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ service: 'minimal-relay', version: '0.1.0' }));
    return;
  }

  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get('device') || url.searchParams.get('id');
  const token = url.searchParams.get('token') || null;

  if (!deviceId) {
    ws.close(4002, 'missing device id');
    return;
  }

  clients.set(String(deviceId), ws);
  logMeta('device connected', { deviceId, token: token ? '****' : null, connected: clients.size });

  ws.on('message', (raw) => {
    // Expect only control pings from device; do not store payloads
    try {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong' }));
      }
    } catch (e) {
      // ignore
    }
  });

  ws.on('close', () => {
    clients.delete(String(deviceId));
    logMeta('device disconnected', { deviceId, connected: clients.size });
  });
});

server.listen(PORT, () => {
  console.log(`[relay] Minimal relay listening on port ${PORT}`);
  console.log('[relay] WebSocket endpoint: ws://<host>:' + PORT + '/?device=<id>&token=<token>');
  console.log('[relay] Forward endpoint: POST http://<host>:' + PORT + '/forward');
});
