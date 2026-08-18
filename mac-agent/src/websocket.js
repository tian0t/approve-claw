const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');
const RequestLifecycleManager = require('./request_lifecycle');

const CONFIG_PATH = path.join(__dirname, '../config.json');
const RELAY_URL = process.env.RELAY_URL || null;
const https = require('https');
const http = require('http');
const { encryptBox } = require('./crypto');
const HEARTBEAT_INTERVAL_MS = 30000;
const MAX_AUTH_ATTEMPTS = 3;
const REQUEST_TIMEOUT_MS = Number(process.env.WATCHAPPROVE_REQUEST_TIMEOUT_MS || 30000);

function getLanIps() {
  const ifaces = os.networkInterfaces();
  const ips = [];
  for (const name of Object.keys(ifaces)) {
    for (const iface of ifaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        ips.push(iface.address);
      }
    }
  }
  return ips;
}

class WatchWebSocketServer {
  constructor(port = 8080, onDecision, detector, host = '0.0.0.0', configPath = CONFIG_PATH) {
    this.port = port;
    this.host = host;
    this.onDecision = onDecision || (() => {});
    this.detector = detector;
    this.configPath = configPath;
    this.wss = null;
    this.heartbeatTimer = null;
    this.onceReady = null;
    this._actualPort = null;

    this.pairingCode = Math.floor(100000 + Math.random() * 900000).toString();
    this.authToken = null;
    this.authenticatedClients = new Set();
    this.completedRequestIds = new Set();

    this.lifecycle = new RequestLifecycleManager({
      timeoutMs: Number.isFinite(REQUEST_TIMEOUT_MS) && REQUEST_TIMEOUT_MS > 0 ? REQUEST_TIMEOUT_MS : 30000,
      eventLogPath: path.join(path.dirname(this.configPath), 'events.jsonl'),
      onActivate: (request) => {
        if (this.detector) {
          this.detector.pendingRequest = request;
        }
        this.broadcast({
          type: 'confirmation_request',
          request,
        });
      },
      onResolve: ({ request, selectedOptionKey, action, reason, source, dispatch }) => {
        if (this.detector && this.detector.pendingRequest && this.detector.pendingRequest.id === request.id) {
          this.detector.acknowledge();
        }
        this.completedRequestIds.add(request.id);
        if (dispatch) {
          // Real user decision: route it to the owning engine and confirm on devices.
          this.onDecision(request.id, action, { selectedOptionKey, reason, source, request });
          this.broadcast({
            type: 'confirmation_completed',
            id: request.id,
            action,
            selectedOptionKey,
            reason,
          });
        } else {
          // Clear-only (timeout/superseded/cancelled): dismiss the card on
          // devices without dispatching anything to the desktop app.
          this.broadcast({
            type: 'confirmation_cancelled',
            id: request.id,
            reason,
          });
        }
      },
    });

    this.loadToken();
  }

  get actualPort() {
    return this._actualPort || this.port;
  }

  loadToken() {
    try {
      if (fs.existsSync(this.configPath)) {
        const config = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
        this.authToken = config.authToken || null;
        if (config.authToken) {
          fs.chmodSync(this.configPath, 0o600);
        }
      }
    } catch (e) {
      console.error('Failed to load auth token:', e);
    }
  }

  saveToken(token) {
    try {
      this.authToken = token;
      fs.writeFileSync(this.configPath, JSON.stringify({ authToken: token }, null, 2));
      fs.chmodSync(this.configPath, 0o600);
    } catch (e) {
      console.error('Failed to save auth token:', e);
    }
  }

  start() {
    this.wss = new WebSocketServer({ port: this.port, host: this.host });

    this.onceReady = new Promise((resolve) => {
      this.wss.on('listening', () => {
        this._actualPort = this.wss.address().port;
        resolve();
      });
    });

    this.wss.on('error', (err) => {
      if (err.code === 'EADDRINUSE') {
        console.error(`\nPort ${this.port} is already in use.`);
        console.error('Stop the other instance, or set WATCHAPPROVE_PORT to use a different port.\n');
        process.exit(1);
      }
      console.error('WebSocket server error:', err.message);
    });

    const lanIps = getLanIps();
    console.log('\n=============================================');
    console.log('WatchApprove WebSocket Server starting...');
    console.log(`Port: ${this.port}  Host: ${this.host}`);
    if (lanIps.length > 0) {
      console.log(`LAN address${lanIps.length > 1 ? 'es' : ''}: ${lanIps.join(', ')}`);
    }
    if (this.authToken) {
      console.log('Device pairing: Existing paired device can reconnect.');
    } else {
      console.log(`Pairing PIN: \x1b[36m${this.pairingCode}\x1b[0m`);
      console.log('Enter this PIN on your iPhone App to pair your device.');
    }
    console.log('=============================================\n');

    this.wss.on('connection', (ws, req) => {
      try {
        const url = new URL(req.url, `http://${req.headers.host}`);
        ws._deviceId = url.searchParams.get('device') || url.searchParams.get('id') || null;
      } catch (e) {
        ws._deviceId = null;
      }
      let isClientAuthenticated = false;
      let authAttempts = 0;

      ws.isAlive = true;
      ws.on('pong', () => {
        ws.isAlive = true;
      });
      ws.on('error', (err) => {
        console.error('WebSocket client error:', err.message);
      });

      ws.on('message', (message) => {
        try {
          const data = JSON.parse(message);

          if (data.type === 'auth') {
            if (data.token && this.authToken && data.token === this.authToken) {
              isClientAuthenticated = true;
              this.authenticatedClients.add(ws);
              ws.send(JSON.stringify({ type: 'auth_success', token: this.authToken }));
              console.log('Paired iPhone connected successfully.');
              this.resendPending(ws);
            } else if (data.code && data.code === this.pairingCode) {
              isClientAuthenticated = true;
              const newToken = crypto.randomBytes(32).toString('hex');
              this.saveToken(newToken);
              this.authenticatedClients.add(ws);
              ws.send(JSON.stringify({ type: 'auth_success', token: newToken }));
              console.log('iPhone paired successfully with PIN code.');
              this.resendPending(ws);
            } else {
              authAttempts += 1;
              if (authAttempts >= MAX_AUTH_ATTEMPTS) {
                ws.send(JSON.stringify({ type: 'auth_fail', message: 'Too many invalid attempts.' }));
                ws.close(4001, 'Too many invalid attempts.');
                console.log('Connection closed: too many invalid auth attempts.');
              } else {
                ws.send(JSON.stringify({ type: 'auth_fail', message: 'Invalid pairing PIN or token.' }));
                console.log('Failed connection attempt: invalid PIN/token.');
              }
            }
            return;
          }

          if (!isClientAuthenticated) {
            ws.send(JSON.stringify({ type: 'error', message: 'Unauthenticated.' }));
            ws.close();
            return;
          }

          if (data.type === 'confirmation_response') {
            const { id, action, selectedOptionKey } = data;
            if (!id || (!action && !selectedOptionKey)) {
              ws.send(JSON.stringify({ type: 'error', message: 'Invalid confirmation_response payload.' }));
              return;
            }
            if (!selectedOptionKey && action && action !== 'approve' && action !== 'reject') {
              ws.send(JSON.stringify({ type: 'error', message: 'Invalid confirmation_response payload.' }));
              return;
            }

            const request = this.lifecycle.getActiveRequest(id);
            if (!request) {
              ws.send(JSON.stringify({ type: 'error', message: 'Request is no longer active.' }));
              return;
            }

            const resolvedOptionKey = selectedOptionKey || this.lifecycle.mapLegacyAction(request, action);
            const resolvedAction = this.optionKeyToAction(request, resolvedOptionKey, action);
            console.log(`Received decision from Watch/iPhone for request [${id}]: \x1b[32m${resolvedOptionKey}\x1b[0m`);
            this.lifecycle.resolve(id, {
              selectedOptionKey: resolvedOptionKey,
              action: resolvedAction,
              source: 'client',
            });
          }
        } catch (e) {
          console.error('Error handling WebSocket message:', e);
        }
      });

      ws.on('close', () => {
        this.authenticatedClients.delete(ws);
        if (isClientAuthenticated) {
          console.log('iPhone client disconnected.');
        }
      });
    });

    this.heartbeatTimer = setInterval(() => {
      for (const client of this.wss.clients) {
        if (client.isAlive === false) {
          client.terminate();
          continue;
        }
        client.isAlive = false;
        client.ping();
      }
    }, HEARTBEAT_INTERVAL_MS);
    if (this.heartbeatTimer.unref) {
      this.heartbeatTimer.unref();
    }
  }

  resendPending(ws) {
    for (const request of this.lifecycle.listActiveRequests()) {
      if (this.completedRequestIds.has(request.id)) continue;
      ws.send(JSON.stringify({
        type: 'confirmation_request',
        request,
      }));
      console.log(`Resent active request to new client: [${request.id}]`);
    }
  }

  sendRequest(request) {
    console.log(`Sending confirmation request to Watch/iPhone: [${request.id}] ${request.command}`);
    const queued = this.lifecycle.enqueue(request);
    if (queued.status === 'duplicate') {
      console.log(`Dropped duplicate detection for [${request.id}] (already active: ${request.agent}).`);
      return queued.status;
    }

    // If relay URL configured and target device offline, forward encrypted payload via relay
    const targetDeviceId = (request.targetDeviceId || request.target || (request.agent && request.agent.replace(/\s+/g, '-').toLowerCase()));
    const localWs = this.authenticatedClients && Array.from(this.authenticatedClients).find((ws) => ws._deviceId === String(targetDeviceId));
    if (RELAY_URL && !localWs) {
      // Try to read recipient public key from config
      let cfg = null;
      try {
        if (fs.existsSync(this.configPath)) {
          cfg = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
        }
      } catch (e) {
        cfg = null;
      }

      const devices = cfg && cfg.pairedDevices ? cfg.pairedDevices : {};
      const recipient = devices[String(targetDeviceId)];
      if (recipient && recipient.publicKey) {
        try {
          const plain = JSON.stringify({ type: 'confirmation_request', request });
          const encrypted = encryptBox(plain, cfg.agentSecretKey, recipient.publicKey);

          const payload = JSON.stringify({ to: String(targetDeviceId), payload: encrypted });
          const relayUrl = new URL(RELAY_URL);
          const isHttps = relayUrl.protocol === 'https:';
          const opts = {
            hostname: relayUrl.hostname,
            port: relayUrl.port || (isHttps ? 443 : 80),
            path: '/forward',
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
          };
          const req = (isHttps ? https : http).request(opts, (res) => {
            let buf = '';
            res.on('data', (c) => buf += c);
            res.on('end', () => {
              try { console.log('[relay] forward response', res.statusCode, buf); } catch (e) {}
            });
          });
          req.on('error', (e) => { console.error('[relay] request error', e && e.message); });
          req.write(payload);
          req.end();

          this.logMeta('forwarded via relay', { to: targetDeviceId });
          return queued.status;
        } catch (e) {
          console.error('[relay] encrypt/forward error', e && e.message);
        }
      }
    }

    return queued.status;
  }

  cancelRequest(requestId) {
    console.log(`Cancelling confirmation request: [${requestId}]`);
    this.lifecycle.resolve(requestId, {
      action: 'clear',
      reason: 'cancelled',
      source: 'system',
      dispatch: false,
    });
  }

  broadcastCleared(requestId) {
    this.broadcast({
      type: 'confirmation_cancelled',
      id: requestId,
    });
  }

  broadcast(messageObj) {
    const payload = JSON.stringify(messageObj);
    for (const client of this.authenticatedClients) {
      if (client.readyState === 1) {
        client.send(payload);
      }
    }
  }

  close() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    if (this.wss) {
      for (const client of this.wss.clients) {
        client.terminate();
      }
      this.wss.close();
    }
    this.lifecycle.close();
  }

  optionKeyToAction(request, selectedOptionKey, fallbackAction) {
    if (selectedOptionKey === 'approve' || selectedOptionKey === 'reject') {
      return selectedOptionKey;
    }

    const opt = (request.optionsList || []).find((item) => String(item.key) === String(selectedOptionKey));
    if (opt) {
      return opt.isDestructive ? 'reject' : 'approve';
    }
    return fallbackAction || 'reject';
  }
}

module.exports = WatchWebSocketServer;
