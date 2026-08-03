const pty = require('node-pty');
const ConfirmationDetector = require('./detector');

console.log('Running detector debug test...');
const detector = new ConfirmationDetector();

const ptyProcess = pty.spawn('node', ['src/mock-agent.js'], {
  name: 'xterm-256color',
  cols: 80,
  rows: 24,
  cwd: process.cwd(),
  env: process.env
});

ptyProcess.onData((data) => {
  console.log('\n--- RAW CHUNK ---');
  console.log(JSON.stringify(data));
  
  detector.feed(data);
  const request = detector.detect('Mock Agent');
  if (request) {
    console.log('\n>>> MATCH FOUND! <<<');
    console.log(request);
    
    // Auto-approve after 1 second so the test continues
    setTimeout(() => {
      console.log('\n[Auto-approving via stdin]');
      ptyProcess.write('y\r');
      detector.pendingRequest = null;
    }, 1000);
  }
});

ptyProcess.onExit(() => {
  console.log('\nTest completed.');
  process.exit(0);
});
