const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CONFIG_PATH = path.join(__dirname, '../config.json');
const HEARTBEAT_INTERVAL_MS = 30000;
const MAX_AUTH_ATTEMPTS = 3;

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

    this.wss.on('connection', (ws) => {
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
            const { id, action } = data;
            if (!id || (action !== 'approve' && action !== 'reject')) {
              ws.send(JSON.stringify({ type: 'error', message: 'Invalid confirmation_response payload.' }));
              return;
            }
            console.log(`Received decision from Watch/iPhone for request [${id}]: \x1b[32m${action}\x1b[0m`);
            this.onDecision(id, action);
            this.broadcast({ type: 'confirmation_completed', id, action });
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
    if (this.detector && this.detector.pendingRequest) {
      ws.send(JSON.stringify({
        type: 'confirmation_request',
        request: this.detector.pendingRequest,
      }));
      console.log(`Resent pending request to new client: [${this.detector.pendingRequest.id}]`);
    }
  }

  sendRequest(request) {
    console.log(`Sending confirmation request to Watch/iPhone: [${request.id}] ${request.command}`);
    this.broadcast({
      type: 'confirmation_request',
      request,
    });
  }

  cancelRequest(requestId) {
    console.log(`Cancelling confirmation request: [${requestId}]`);
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
  }
}

module.exports = WatchWebSocketServer;
