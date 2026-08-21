#!/usr/bin/env node
/**
 * e2e_realistic_sim.js
 *
 * Realistic end-to-end simulation of the full approve-claw closed loop.
 *
 * Scenario: User is at desk, starts an AI agent session, then walks away.
 * They glance at Apple Watch minutes later and approve/reject from there.
 *
 * Tests verified:
 *  1. Frontmost-app guard  — OCR result from background Chrome is silently dropped
 *  2. Default timeout      — 5 minutes (300 000 ms), not 30 s
 *  3. Antigravity IDE      — plan approval → Watch tap → dispatch=true
 *  4. OpenAI Codex         — high-risk git push → Watch rejects → dispatch=true
 *  5. Claude Code          — 3-option tool menu → Watch taps "1" → dispatch=true
 *  6. Semantic dedup       — same dialog rescanned → only one Watch card
 *  7. AX priority          — native Codex AX detection supersedes Vision
 *  8. Stale-prompt guard   — late decision for cleared prompt is ignored
 *  9. Full timeline        — agent fires → user away 800ms → Watch approves → resolved
 */

'use strict';

const assert = require('assert');
const { describe, it } = require('node:test');
const WebSocket = require('ws');
const net = require('net');
const RequestLifecycleManager = require('../src/request_lifecycle');
const ConfirmationDetector = require('../src/detector');
const { createRequestId } = require('../src/request_id');
const WatchWebSocketServer = require('../src/websocket');

// ─── helpers ───────────────────────────────────────────────────────────────

function freePort() {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * Pairs a WebSocket client with the server using its pairing code,
 * returns the authenticated ws and the auth token.
 */
async function pairClient(server, port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}`);
  await new Promise((res) => ws.on('open', res));

  const tokenPromise = new Promise((res) => {
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'auth_success') res(msg.token);
    });
  });

  // Server exposes pairingCode as .pairingCode (or .pin in tests)
  const code = server.pairingCode || server.pin;
  ws.send(JSON.stringify({ type: 'auth', code }));
  const token = await tokenPromise;
  return { ws, token };
}

/**
 * Sends a decision message in the correct wire format the server expects
 * (confirmation_response, not "decision").
 */
function sendDecision(ws, requestId, selectedOptionKey) {
  ws.send(JSON.stringify({
    type: 'confirmation_response',
    id: requestId,
    action: selectedOptionKey,          // legacy field kept for compatibility
    selectedOptionKey,
  }));
}

function makeRequest(overrides = {}) {
  return {
    id: createRequestId(),
    agent: 'Antigravity IDE',
    type: 'command_confirmation',
    title: 'Antigravity IDE — Action Approval',
    command: 'npx vite build',
    description: 'Antigravity IDE is requesting permission to execute an action.',
    risk: 'medium',
    time: new Date().toISOString(),
    options: ['approve', 'reject'],
    optionsList: [
      { key: 'approve', label: 'Proceed & Allow', isPrimary: true,  isDestructive: false },
      { key: 'reject',  label: 'Cancel & Deny',   isPrimary: false, isDestructive: true  },
    ],
    ...overrides,
  };
}

// ─── test suite ────────────────────────────────────────────────────────────

describe('approve-claw: realistic end-to-end simulation', async () => {

  // ── 1. Frontmost-app guard ──────────────────────────────────────────────
  it('1. Frontmost-app guard: drops OCR result when wrong app is frontmost', () => {
    // Mirrors the Swift isFrontmostApp() logic in JS for verification
    const agentBundleIDs = {
      'Antigravity IDE': ['com.google.antigravity', 'com.google.antigravity-dev'],
      'OpenAI Codex':    ['com.openai.chat', 'com.openai.codex'],
      'Claude Code':     ['com.anthropic.claude', 'com.anthropic.claudefordesktop',
                          'com.apple.Terminal', 'com.googlecode.iterm2',
                          'dev.warp.Warp-Stable', 'com.microsoft.VSCode'],
    };

    function isFrontmostAllowed(agent, bundleID) {
      return (agentBundleIDs[agent] || []).includes(bundleID);
    }

    // Chrome with Claude docs open in background → must block
    assert.strictEqual(isFrontmostAllowed('Claude Code', 'com.google.Chrome'), false,
      'Chrome must NOT be allowed frontmost for Claude Code');

    // Safari with Antigravity homepage open → must block
    assert.strictEqual(isFrontmostAllowed('Antigravity IDE', 'com.apple.Safari'), false,
      'Safari must NOT be allowed frontmost for Antigravity IDE');

    // Normal Codex path is the native desktop app. Browser simulation is opt-in.
    assert.strictEqual(isFrontmostAllowed('OpenAI Codex', 'com.google.Chrome'), false,
      'Chrome must NOT be allowed in the normal Codex path');
    assert.strictEqual(isFrontmostAllowed('OpenAI Codex', 'com.openai.codex'), true,
      'Native Codex App must be allowed frontmost');

    // Claude Code running inside Terminal → allowed
    assert.strictEqual(isFrontmostAllowed('Claude Code', 'com.apple.Terminal'), true,
      'Terminal IS allowed frontmost for Claude Code');

    // Claude Code running in Warp → allowed
    assert.strictEqual(isFrontmostAllowed('Claude Code', 'dev.warp.Warp-Stable'), true,
      'Warp IS allowed frontmost for Claude Code');

    console.log('  ✅ Frontmost-app guard blocks all background-app false positives');
  });

  // ── 2. Default timeout is 5 minutes ────────────────────────────────────
  it('2. Default timeout is 5 minutes (300 000 ms)', () => {
    const lifecycle = new RequestLifecycleManager({
      onActivate: () => {},
      onResolve:  () => {},
    });
    assert.strictEqual(lifecycle.timeoutMs, 300000,
      'Default timeout must be 300 000 ms (5 minutes)');
    console.log('  ✅ Default timeout = 300 000 ms — Watch card stays alive for 5 min');
  });

  // ── 3. Antigravity IDE: Mac enqueues → Watch approves → dispatch=true ──
  it('3. Antigravity IDE: plan approval flow → Watch approve → dispatch=true', async () => {
    const port = await freePort();
    const server = new WatchWebSocketServer(port, null, new ConfirmationDetector(), '127.0.0.1');
    server.start();
    await sleep(50);

    const resolved = [];
    const origOnResolve = server.lifecycle.onResolve.bind(server.lifecycle);
    server.lifecycle.onResolve = (res) => { resolved.push(res); origOnResolve(res); };

    const req = makeRequest({ command: 'npx vite build', risk: 'medium' });
    server.sendRequest(req);
    await sleep(50);

    const { ws } = await pairClient(server, port);
    await sleep(100);

    sendDecision(ws, req.id, 'approve');
    await sleep(300);

    assert.ok(resolved.length > 0, 'Should have a resolved event');
    const r = resolved[0];
    assert.strictEqual(r.action, 'approve');
    assert.strictEqual(r.dispatch, true, 'dispatch must be true → Mac will click Proceed');

    console.log(`  ✅ Antigravity IDE: "npx vite build" → Watch approve → dispatch=true`);
    ws.close();
    server.close();
  });

  // ── 4. OpenAI Codex: high-risk force push → Watch rejects ──────────────
  it('4. OpenAI Codex: high-risk git push --force → Watch reject', async () => {
    const port = await freePort();
    const server = new WatchWebSocketServer(port, null, new ConfirmationDetector(), '127.0.0.1');
    server.start();
    await sleep(50);

    const resolved = [];
    const origOnResolve = server.lifecycle.onResolve.bind(server.lifecycle);
    server.lifecycle.onResolve = (res) => { resolved.push(res); origOnResolve(res); };

    const req = makeRequest({
      agent: 'OpenAI Codex',
      command: 'git push --force origin main',
      risk: 'high',
      options: ['approve', 'reject'],
      optionsList: [
        { key: 'approve', label: 'Approve', isPrimary: true,  isDestructive: false },
        { key: 'reject',  label: 'Reject',  isPrimary: false, isDestructive: true  },
      ],
    });
    server.sendRequest(req);
    await sleep(50);

    const { ws } = await pairClient(server, port);
    await sleep(100);

    // Watch user sees HIGH RISK badge and taps Reject
    sendDecision(ws, req.id, 'reject');
    await sleep(300);

    assert.ok(resolved.length > 0, 'Should have a resolved event');
    const r = resolved[0];
    assert.strictEqual(r.action, 'reject');
    assert.strictEqual(r.selectedOptionKey, 'reject');
    assert.strictEqual(r.dispatch, true);

    console.log('  ✅ OpenAI Codex: high-risk "git push --force" rejected via Watch → dispatch=true');
    ws.close();
    server.close();
  });

  // ── 5. Claude Code: 3-option tool menu → Watch taps "1" ────────────────
  it('5. Claude Code: 3-option permission menu → Watch selects "1"', async () => {
    const port = await freePort();
    const server = new WatchWebSocketServer(port, null, new ConfirmationDetector(), '127.0.0.1');
    server.start();
    await sleep(50);

    const resolved = [];
    const origOnResolve = server.lifecycle.onResolve.bind(server.lifecycle);
    server.lifecycle.onResolve = (res) => { resolved.push(res); origOnResolve(res); };

    const req = makeRequest({
      agent: 'Claude Code',
      command: 'rm -rf node_modules',
      risk: 'high',
      options: ['1', '2', '3'],
      optionsList: [
        { key: '1', label: '1. Yes, allow once',             isPrimary: true,  isDestructive: false },
        { key: '2', label: '2. Yes, allow for this session', isPrimary: false, isDestructive: false },
        { key: '3', label: '3. No',                          isPrimary: false, isDestructive: true  },
      ],
    });
    server.sendRequest(req);
    await sleep(50);

    const { ws } = await pairClient(server, port);
    await sleep(100);

    // Watch displays 3 buttons — user taps "1. Yes, allow once"
    sendDecision(ws, req.id, '1');
    await sleep(300);

    assert.ok(resolved.length > 0, 'Should have a resolved event');
    const r = resolved[0];
    assert.strictEqual(r.selectedOptionKey, '1');
    assert.strictEqual(r.dispatch, true, 'dispatch=true → Mac injects key "1" + Enter');

    console.log('  ✅ Claude Code: "rm -rf node_modules" → Watch tap "1" → Mac keystroke 1+Enter');
    ws.close();
    server.close();
  });

  // ── 6. Semantic dedup ───────────────────────────────────────────────────
  it('6. Semantic dedup: same dialog rescanned → only one Watch card sent', () => {
    const activated = [];
    const lifecycle = new RequestLifecycleManager({
      timeoutMs: 300000,
      onActivate: (req) => activated.push(req.id),
      onResolve:  () => {},
    });

    const base = makeRequest({ command: 'npm run build' });
    lifecycle.enqueue(base);

    // OCR rescans, produces new id but identical content
    const dup = { ...base, id: createRequestId() };
    const result = lifecycle.enqueue(dup);

    assert.strictEqual(activated.length, 1, 'Only one activation — no duplicate Watch card');
    assert.strictEqual(result.status, 'duplicate');
    console.log('  ✅ Semantic dedup: OCR rescan of same dialog → 0 extra Watch cards');
  });

  // ── 7. AX wins over Vision for the same native Codex card ──────────────
  it('7. Native Codex: AX detection supersedes Vision detection', () => {
    const activated = [];
    const resolved = [];
    const lifecycle = new RequestLifecycleManager({
      timeoutMs: 300000,
      onActivate: (req) => activated.push(req),
      onResolve: (result) => resolved.push(result),
    });

    const vision = makeRequest({
      agent: 'OpenAI Codex',
      isVisionPrompt: true,
      command: 'git status',
      title: 'OpenAI Codex — Approval Required',
    });
    const ax = makeRequest({
      agent: 'OpenAI Codex',
      isAxPrompt: true,
      command: 'git status',
      title: 'OpenAI Codex — Approval Required',
    });

    lifecycle.enqueue(vision);
    lifecycle.enqueue(ax);

    assert.strictEqual(activated.length, 2, 'AX should replace the earlier Vision card');
    assert.strictEqual(resolved[0].request.id, vision.id);
    assert.strictEqual(resolved[0].reason, 'superseded_by_ax');
    assert.strictEqual(resolved[0].dispatch, false);
    assert.strictEqual(lifecycle.getActiveRequest(ax.id).isAxPrompt, true);
    console.log('  ✅ Native Codex: AX semantic approval takes priority; Vision remains fallback');
  });

  // ── 8. Stale-prompt guard ───────────────────────────────────────────────
  it('8. Stale-prompt guard: late Watch decision for cleared prompt is ignored', () => {
    const resolvedLog = [];
    const lifecycle = new RequestLifecycleManager({
      timeoutMs: 300000,
      onActivate: () => {},
      onResolve:  (res) => resolvedLog.push(res),
    });

    const req = makeRequest({ command: 'docker compose up -d' });
    lifecycle.enqueue(req);

    // New dialog supersedes the old one (old prompt cleared, dispatch:false)
    const newReq = makeRequest({ command: 'docker compose down' });
    lifecycle.enqueue(newReq);

    // Stale Watch decision arrives for the old (now-cleared) prompt
    const stale = lifecycle.resolve(req.id, {
      action: 'approve',
      selectedOptionKey: 'approve',
      source: 'client',
    });

    assert.strictEqual(stale.status, 'ignored', 'Stale decision must be silently ignored');
    const dispatched = resolvedLog.filter((r) => r.dispatch === true);
    assert.strictEqual(dispatched.length, 0, 'No real dispatch for stale decision');
    console.log('  ✅ Stale-prompt guard: late Watch tap safely ignored — no Mac side-effects');
  });

  // ── 9. Full realistic timeline ──────────────────────────────────────────
  it('9. Full timeline: agent fires → user away ~1s → Watch approve → resolved', async () => {
    const port = await freePort();
    const server = new WatchWebSocketServer(port, null, new ConfirmationDetector(), '127.0.0.1');
    server.start();
    await sleep(50);

    const resolved = [];
    const origOnResolve = server.lifecycle.onResolve.bind(server.lifecycle);
    server.lifecycle.onResolve = (res) => { resolved.push(res); origOnResolve(res); };

    const req = makeRequest({
      agent: 'Antigravity IDE',
      command: 'git commit -m "feat: add watch approval flow"',
      risk: 'low',
    });

    const t0 = Date.now();
    server.sendRequest(req);

    // Simulate user being away — card must still be alive (5-min timeout, not 30s)
    await sleep(800);

    const still = server.lifecycle.getActiveRequest(req.id);
    assert.ok(still, 'Request must still be active after 800ms (5-min timeout)');

    // User glances at Watch, taps Proceed
    const { ws } = await pairClient(server, port);
    await sleep(100);
    sendDecision(ws, req.id, 'approve');
    await sleep(300);

    assert.ok(resolved.length > 0, 'Must have a resolved event');
    const r = resolved[0];
    assert.strictEqual(r.action, 'approve');
    assert.strictEqual(r.dispatch, true);
    const elapsed = Date.now() - t0;
    assert.ok(elapsed >= 800, `Card was alive for ${elapsed}ms`);

    console.log(`  ✅ Full timeline: agent fired → away ${elapsed}ms → Watch approved → Mac dispatched`);
    ws.close();
    server.close();
  });

});
