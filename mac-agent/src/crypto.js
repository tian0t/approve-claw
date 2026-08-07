const nacl = require('tweetnacl');
// tweetnacl uses Uint8Array; use Buffer for base64 conversions
nacl.util = require('tweetnacl-util');

function generateKeypair() {
  const kp = nacl.box.keyPair();
  return {
    publicKey: Buffer.from(kp.publicKey).toString('base64'),
    secretKey: Buffer.from(kp.secretKey).toString('base64'),
  };
}

function base64ToUint8(s) {
  return Buffer.from(s, 'base64');
}

function uint8ToBase64(u8) {
  return Buffer.from(u8).toString('base64');
}

// encrypt message (string) using senderSecretKey (base64) and recipientPublicKey (base64)
function encryptBox(message, senderSecretKey_b64, recipientPublicKey_b64) {
  const nonce = nacl.randomBytes(nacl.box.nonceLength);
  const senderSecret = base64ToUint8(senderSecretKey_b64);
  const recipientPub = base64ToUint8(recipientPublicKey_b64);
  const msgUint8 = Buffer.from(message);
  const boxed = nacl.box(msgUint8, nonce, recipientPub, senderSecret);
  // return base64 { nonce, boxed }
  return JSON.stringify({ nonce: uint8ToBase64(nonce), box: uint8ToBase64(boxed) });
}

// decrypt with recipientSecretKey (base64) and senderPublicKey (base64)
function decryptBox(payloadJson, recipientSecretKey_b64, senderPublicKey_b64) {
  const obj = typeof payloadJson === 'string' ? JSON.parse(payloadJson) : payloadJson;
  const nonce = base64ToUint8(obj.nonce);
  const box = base64ToUint8(obj.box);
  const recipientSecret = base64ToUint8(recipientSecretKey_b64);
  const senderPub = base64ToUint8(senderPublicKey_b64);
  const opened = nacl.box.open(box, nonce, senderPub, recipientSecret);
  if (!opened) return null;
  return Buffer.from(opened).toString();
}

module.exports = { generateKeypair, encryptBox, decryptBox };
