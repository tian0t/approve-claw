const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');
const WatchWebSocketServer = require('../src/websocket');

function tempConfigPath() {
  return path.join(os.tmpdir(), `watchapprove-config-${Date.now()}-${Math.random().toString(16).slice(2)}.json`);
}

function open(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

function nextMessage(ws) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timed out waiting for message')), 3000);
    ws.once('message', (raw) => {
      clearTimeout(timer);
      resolve(JSON.parse(raw.toString()));
    });
  });
}

function waitUntil(cond, timeout = 3000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const poll = () => {
      if (cond()) return resolve();
      if (Date.now() - start > timeout) return reject(new Error('timed out waiting for condition'));
      setTimeout(poll, 25);
    };
    poll();
  });
}

function listenBefore(ws, handler) {
  ws.on('message', handler);
  return () => ws.off('message', handler);
}

async function startServer(onDecision) {
  const server = new WatchWebSocketServer(0, onDecision, null, '127.0.0.1', tempConfigPath());
  server.start();
  await server.onceReady;
  return server;
}

async function cleanup(ws, server) {
  if (ws) ws.terminate();
  if (server) server.close();
}

test('rejects an invalid auth token and closes after repeated failures', async () => {
  const server = await startServer();
  let ws;
  try {
    ws = await open(`ws://127.0.0.1:${server.actualPort}`);
    ws.send(JSON.stringify({ type: 'auth', token: 'wrong' }));
    const first = await nextMessage(ws);
    assert.equal(first.type, 'auth_fail');

    ws.send(JSON.stringify({ type: 'auth', token: 'wrong' }));
    const second = await nextMessage(ws);
    assert.equal(second.type, 'auth_fail');

    ws.send(JSON.stringify({ type: 'auth', token: 'wrong' }));
    const third = await nextMessage(ws);
    assert.equal(third.type, 'auth_fail');
  } finally {
    await cleanup(ws, server);
  }
});

test('rejects unauthenticated non-auth messages', async () => {
  const server = await startServer();
  let ws;
  try {
    ws = await open(`ws://127.0.0.1:${server.actualPort}`);
    ws.send(JSON.stringify({ type: 'confirmation_response', id: 'x', action: 'approve' }));
    const msg = await nextMessage(ws);
    assert.equal(msg.type, 'error');
  } finally {
    await cleanup(ws, server);
  }
});

test('pairs with the PIN and relays a decision', async () => {
  const decisions = [];
  const server = await startServer((id, action) => decisions.push({ id, action }));
  let ws;
  try {
    ws = await open(`ws://127.0.0.1:${server.actualPort}`);
    ws.send(JSON.stringify({ type: 'auth', code: server.pairingCode }));
    const auth = await nextMessage(ws);
    assert.equal(auth.type, 'auth_success');
    assert.ok(auth.token && auth.token.length === 64, 'token should be 32 random bytes hex');

    server.sendRequest({
      id: 'req_test',
      agent: 'Codex',
      command: 'npm test',
      options: ['approve', 'reject'],
      optionsList: [
        { key: 'approve', label: 'Approve', isPrimary: true, isDestructive: false },
        { key: 'reject', label: 'Reject', isPrimary: false, isDestructive: true },
      ],
    });
    const requestMsg = await nextMessage(ws);
    assert.equal(requestMsg.type, 'confirmation_request');
    assert.equal(requestMsg.request.id, 'req_test');

    const completedPromise = listenBefore(ws, (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'confirmation_completed') {
        decisions.push({ completed: msg });
      }
    });

    ws.send(JSON.stringify({ type: 'confirmation_response', id: 'req_test', selectedOptionKey: 'approve', action: 'approve' }));
    await waitUntil(() => decisions.some((d) => d.id === 'req_test'));
    await waitUntil(() => decisions.some((d) => d.completed && d.completed.id === 'req_test'));

    assert.equal(decisions.find((d) => d.id === 'req_test').action, 'approve');
    const completed = decisions.find((d) => d.completed).completed;
    assert.equal(completed.action, 'approve');
    completedPromise();
  } finally {
    await cleanup(ws, server);
  }
});

test('ignores invalid decision actions', async () => {
  const decisions = [];
  const server = await startServer((id, action) => decisions.push({ id, action }));
  let ws;
  try {
    ws = await open(`ws://127.0.0.1:${server.actualPort}`);
    ws.send(JSON.stringify({ type: 'auth', code: server.pairingCode }));
    await nextMessage(ws);

    const errorPromise = nextMessage(ws);
    ws.send(JSON.stringify({ type: 'confirmation_response', id: 'req_bad', action: 'yes' }));
    const msg = await errorPromise;
    assert.equal(msg.type, 'error');
    assert.equal(decisions.length, 0);
  } finally {
    await cleanup(ws, server);
  }
});

test('re-authenticates with the saved token after pairing', async () => {
  const configPath = tempConfigPath();
  const savedToken = 'a'.repeat(64);
  fs.writeFileSync(configPath, JSON.stringify({ authToken: savedToken }));
  const server = new WatchWebSocketServer(0, null, null, '127.0.0.1', configPath);
  server.start();
  await server.onceReady;
  let ws;
  try {
    assert.equal(server.authToken, savedToken, 'token should be loaded from config');
    ws = await open(`ws://127.0.0.1:${server.actualPort}`);
    ws.send(JSON.stringify({ type: 'auth', token: savedToken }));
    const auth = await nextMessage(ws);
    assert.equal(auth.type, 'auth_success');
  } finally {
    await cleanup(ws, server);
  }
});

test('uses selectedOptionKey and applies first-write-wins', async () => {
  const decisions = [];
  const server = await startServer((id, action, meta) => decisions.push({ id, action, meta }));
  let ws;
  try {
    ws = await open(`ws://127.0.0.1:${server.actualPort}`);
    ws.send(JSON.stringify({ type: 'auth', code: server.pairingCode }));
    await nextMessage(ws);

    server.sendRequest({
      id: 'req_opts',
      agent: 'Antigravity IDE',
      command: 'node -c index.js',
      optionsList: [
        { key: '1', label: '1. Yes, allow this time', isPrimary: true, isDestructive: false },
        { key: '5', label: '5. No', isPrimary: false, isDestructive: true },
      ],
      options: ['1', '5'],
    });
    await nextMessage(ws);

    ws.send(JSON.stringify({ type: 'confirmation_response', id: 'req_opts', selectedOptionKey: '1' }));
    await waitUntil(() => decisions.length === 1);
    assert.equal(decisions[0].meta.selectedOptionKey, '1');
    assert.equal(decisions[0].action, 'approve');

    ws.send(JSON.stringify({ type: 'confirmation_response', id: 'req_opts', selectedOptionKey: '5' }));
    const error = await nextMessage(ws);
    assert.equal(error.type, 'error');
    assert.equal(decisions.length, 1);
  } finally {
    await cleanup(ws, server);
  }
});
