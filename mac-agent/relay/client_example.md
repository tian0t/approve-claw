Client example (Node.js)

const WebSocket = require('ws');
const ws = new WebSocket('ws://relay.example.com:4000/?device=my-mac-1&token=xxxx');

ws.on('open', () => {
  console.log('connected');
});

ws.on('message', (m) => {
  const data = JSON.parse(m.toString());
  if (data.type === 'relay') {
    // data.payload is opaque; decrypt locally and act on it
    console.log('received relay payload');
  }
});

// Forward from mac-agent to device via relay
const fetch = require('node-fetch');
await fetch('https://relay.example.com/forward', {
  method: 'POST',
  body: JSON.stringify({ to: 'my-iphone-1', payload: encryptedBlob }),
  headers: { 'Content-Type': 'application/json' }
});
