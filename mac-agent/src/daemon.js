const WatchWebSocketServer = require('./websocket');
const ConfirmationDetector = require('./detector');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '../config.json');
const port = Number(process.env.WATCHAPPROVE_PORT || 8080);
const host = process.env.WATCHAPPROVE_HOST || '0.0.0.0';

const detector = new ConfirmationDetector();

let activePty = null;

const server = new WatchWebSocketServer(port, (requestId, action) => {
  if (detector.pendingRequest && detector.pendingRequest.id === requestId) {
    const charToSubmit = action === 'approve' ? 'y\r' : 'n\r';
    console.log(`\n[CLAW Approve Daemon] Forwarding decision '${action}' (${JSON.stringify(charToSubmit)}) to active CLI...`);
    if (activePty) {
      activePty.write(charToSubmit);
    }
    detector.acknowledge();
  }
}, detector, host, CONFIG_PATH);

server.start();

console.log("\n🟢 CLAW Approve Permanent Daemon active on port 8080.");
console.log("Your iPhone & Apple Watch will stay CONNECTED 24/7.\n");
