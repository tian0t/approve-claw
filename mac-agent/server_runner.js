const WatchWebSocketServer = require('./src/websocket');
const ConfirmationDetector = require('./src/detector');

const detector = new ConfirmationDetector();
const server = new WatchWebSocketServer(8080, (id, action) => {
  console.log(`[DECISION RECEIVED] Request ${id} -> Action: ${action}`);
}, detector, '0.0.0.0');

server.start();

console.log("CLAW Mac Agent Server running on port 8080...");

// Keep process running
setInterval(() => {}, 1000);

// Broadcast a sample prompt to connected devices after 3 seconds
setTimeout(() => {
  console.log("\n[Simulating AI Agent Prompt]");
  server.sendRequest({
    id: "req_sim_" + Date.now(),
    agent: "CLAW Agent",
    type: "command_confirmation",
    title: "Permission Required",
    description: "Execute build script?",
    command: "npm run build --prefix ./app",
    risk: "medium"
  });
}, 3000);
