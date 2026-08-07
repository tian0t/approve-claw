Minimal Relay

This is a minimal relay server used for the APNs/proxy beta flow.

- Run: `node relay_server.js`
- WS clients connect: `ws://host:4000/?device=<deviceId>&token=<token>`
- Forward: POST /forward { to: "deviceId", payload: <opaque base64 or JSON> }

Security notes:
- Relay never writes payloads to disk in cleartext
- Relay does not interpret payloads; it only forwards opaque blobs
- For production, run behind TLS and authenticate device tokens
