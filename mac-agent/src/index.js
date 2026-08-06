#!/usr/bin/env node

const os = require('os');
const execSync = require('child_process').execSync;
const WatchWebSocketServer = require('./websocket');
const ConfirmationDetector = require('./detector');
const { runTerminal } = require('./terminal');
const AntigravityIdeBridge = require('./antigravity_ide_bridge');

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

function binaryExists(cmd) {
  try {
    execSync(`which ${cmd}`, { stdio: 'ignore' });
    return true;
  } catch (e) {
    return false;
  }
}

function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === '-h' || args[0] === '--help') {
    console.log('Usage: watchapprove <command> [args...]');
    console.log('       watchapprove daemon (runs 24/7 background server)');
    console.log('Example: watchapprove claude');
    console.log('Example: watchapprove antigravity');
    console.log('Example: watchapprove daemon');
    console.log('');
    console.log('Environment variables:');
    console.log('  WATCHAPPROVE_PORT  WebSocket port (default: 8080)');
    console.log('  WATCHAPPROVE_HOST  Bind address   (default: 0.0.0.0)');
    process.exit(args.length === 0 ? 1 : 0);
  }

  const port = Number(process.env.WATCHAPPROVE_PORT || process.env.PORT || 8080);
  const host = process.env.WATCHAPPROVE_HOST || '0.0.0.0';

  const detector = new ConfirmationDetector();
  let terminalController = null;

  const onDecision = (requestId, action) => {
    if (terminalController) {
      terminalController.handleDecision(requestId, action);
    }
  };

  const server = new WatchWebSocketServer(port, onDecision, detector, host);
  server.start();

  // Start Antigravity IDE Real-Time Brain Watcher
  const ideBridge = new AntigravityIdeBridge(server, detector);
  ideBridge.start();

  const rawCommand = args[0];
  const targetArgs = args.slice(1);

  // If user requests 'daemon' or 'server', run 24/7 background mode
  if (rawCommand === 'daemon' || rawCommand === 'server') {
    console.log('\n🟢 CLAW Approve Permanent Daemon mode active on port 8080.');
    console.log('Your iPhone & Apple Watch will stay CONNECTED 24/7.\n');
    return;
  }

  let targetCommand = rawCommand;

  // Smart fallback resolution for Antigravity IDE / AGY / Codex
  if (targetCommand === 'codex') {
    if (!binaryExists('codex') && binaryExists('/opt/homebrew/bin/codex')) {
      targetCommand = '/opt/homebrew/bin/codex';
    }
    console.log(`\n[CLAW Approve] Launching Codex CLI (${targetCommand})...`);
  } else if (targetCommand === 'antigravity') {
    if (!binaryExists('antigravity')) {
      if (binaryExists('agy')) {
        targetCommand = 'agy';
      } else {
        console.log('\n[CLAW Approve] Antigravity IDE detected! Running in Permanent Daemon mode with System Events Bridge.');
        console.log('Your iPhone & Apple Watch will stay CONNECTED 24/7 for Antigravity IDE prompts.\n');
        return;
      }
    }
  }

  try {
    terminalController = runTerminal(targetCommand, targetArgs, server, detector);
  } catch (error) {
    console.error(`Failed to start terminal command: ${targetCommand}`);
    console.error(error);
    server.close();
    process.exit(1);
  }

  const shutdown = () => {
    console.log('\nShutting down...');
    if (terminalController && terminalController.close) {
      terminalController.close();
    }
    server.close();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main();
