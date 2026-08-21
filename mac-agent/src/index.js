#!/usr/bin/env node

const os = require('os');
const WatchWebSocketServer = require('./websocket');
const VisionBridge = require('./vision_bridge');
const AxBridge = require('./ax_bridge');
const ConfirmationDetector = require('./detector');

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

function main() {
  const args = process.argv.slice(2);

  if (args.includes('-h') || args.includes('--help')) {
    console.log('approve-claw v2.0 - Universal Screen Vision Agent Companion');
    console.log('');
    console.log('Usage: watchapprove [options]');
    console.log('');
    console.log('Options:');
    console.log('  -p, --port <port>   WebSocket port (default: 8080)');
    console.log('  -h, --help          Show help message');
    console.log('');
    console.log('Environment variables:');
    console.log('  WATCHAPPROVE_PORT   WebSocket port (default: 8080)');
    console.log('  WATCHAPPROVE_HOST   Bind address   (default: 0.0.0.0)');
    process.exit(0);
  }

  let port = Number(process.env.WATCHAPPROVE_PORT || process.env.PORT || 8080);
  const portIdx = args.findIndex((a) => a === '-p' || a === '--port');
  if (portIdx !== -1 && args[portIdx + 1]) {
    port = Number(args[portIdx + 1]);
  }
  const host = process.env.WATCHAPPROVE_HOST || '0.0.0.0';

  console.log('\n=============================================================');
  console.log('🚀 approve-claw v2.0: Universal Apple Vision Screen Engine');
  console.log('=============================================================');

  // Start WebSocket Gateway
  const detector = new ConfirmationDetector();
  const server = new WatchWebSocketServer(port, null, detector, host);
  server.start();

  // Start Universal Screen Vision OCR Engine (fallback detector + click dispatcher)
  const visionBridge = new VisionBridge(server);
  visionBridge.start();

  // Start Native AX (Accessibility) Observer (primary detector + semantic button press)
  const axBridge = new AxBridge(server, detector, visionBridge);
  axBridge.start();

  console.log('\niPhone & Apple Watch are ready to connect.');
  console.log('Leave your AI agent running on screen — we will notify your watch on any prompt!\n');

  const shutdown = () => {
    console.log('\nStopping approve-claw daemon...');
    visionBridge.stop();
    axBridge.stop();
    server.close();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main();
