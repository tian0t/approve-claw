const fs = require('fs');
const zlib = require('zlib');
const path = require('path');

function crc32(buf) {
  let crc = -1;
  for (let i = 0; i < buf.length; i++) {
    let byte = buf[i];
    for (let j = 0; j < 8; j++) {
      let bit = (crc ^ byte) & 1;
      crc = (crc >>> 1) ^ (bit ? 0xedb88320 : 0);
      byte >>>= 1;
    }
  }
  return (crc ^ -1) >>> 0;
}

function makeChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  const typeAndData = Buffer.concat([typeBuf, data]);
  crcBuf.writeUInt32BE(crc32(typeAndData), 0);
  return Buffer.concat([len, typeAndData, crcBuf]);
}

function generateIconPNG(size) {
  const width = size;
  const height = size;
  const rawData = Buffer.alloc(height * (1 + width * 4));
  
  const bgDark = [16, 18, 26, 255];
  const bgGlow = [208, 112, 88, 255];
  const cyanEye = [0, 225, 255, 255];
  
  let ptr = 0;
  for (let y = 0; y < height; y++) {
    rawData[ptr++] = 0;
    const ny = (y / height) - 0.5;
    
    for (let x = 0; x < width; x++) {
      const nx = (x / width) - 0.5;
      const dist = Math.sqrt(nx * nx + ny * ny);
      
      let r = 16 + Math.floor(ny * 20);
      let g = 18 + Math.floor(ny * 20);
      let b = 26 + Math.floor(ny * 30);
      let a = 255;
      
      if (dist < 0.45) {
        const glow = (1 - dist / 0.45);
        r = Math.min(255, Math.floor(r + 120 * glow));
        g = Math.min(255, Math.floor(g + 50 * glow));
        b = Math.min(255, Math.floor(b + 40 * glow));
      }
      
      const gx = Math.floor((x / width) * 12);
      const gy = Math.floor((y / height) * 8);
      
      const isBody = (gx >= 2 && gx <= 9 && gy >= 1 && gy <= 5);
      const isEarL = (gx >= 0 && gx <= 1 && gy >= 3 && gy <= 4);
      const isEarR = (gx >= 10 && gx <= 11 && gy >= 3 && gy <= 4);
      const isLeg1 = (gx === 2 && gy >= 6 && gy <= 7);
      const isLeg2 = (gx === 4 && gy >= 6 && gy <= 7);
      const isLeg3 = (gx === 7 && gy >= 6 && gy <= 7);
      const isLeg4 = (gx === 9 && gy >= 6 && gy <= 7);
      const isEyeL = (gx === 4 && gy === 2);
      const isEyeR = (gx === 7 && gy === 2);
      
      if (isEyeL || isEyeR) {
        r = cyanEye[0]; g = cyanEye[1]; b = cyanEye[2]; a = cyanEye[3];
      } else if (isBody || isEarL || isEarR || isLeg1 || isLeg2 || isLeg3 || isLeg4) {
        r = bgGlow[0]; g = bgGlow[1]; b = bgGlow[2]; a = bgGlow[3];
      }
      
      rawData[ptr++] = Math.max(0, Math.min(255, r));
      rawData[ptr++] = Math.max(0, Math.min(255, g));
      rawData[ptr++] = Math.max(0, Math.min(255, b));
      rawData[ptr++] = Math.max(0, Math.min(255, a));
    }
  }

  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const idat = zlib.deflateSync(rawData);
  const iend = Buffer.alloc(0);

  return Buffer.concat([
    sig,
    makeChunk('IHDR', ihdr),
    makeChunk('IDAT', idat),
    makeChunk('IEND', iend)
  ]);
}

const iosIconDir = path.join(__dirname, '../ios/WatchApprove/Assets.xcassets/AppIcon.appiconset');
const watchIconDir = path.join(__dirname, '../ios/WatchApproveWatch/Assets.xcassets/AppIcon.appiconset');

fs.mkdirSync(iosIconDir, { recursive: true });
fs.mkdirSync(watchIconDir, { recursive: true });

const png1024 = generateIconPNG(1024);
const png120 = generateIconPNG(120);
const png180 = generateIconPNG(180);

fs.writeFileSync(path.join(iosIconDir, 'icon-1024.png'), png1024);
fs.writeFileSync(path.join(iosIconDir, 'icon-120.png'), png120);
fs.writeFileSync(path.join(iosIconDir, 'icon-180.png'), png180);

fs.writeFileSync(path.join(watchIconDir, 'icon-1024.png'), png1024);
fs.writeFileSync(path.join(watchIconDir, 'icon-120.png'), png120);
fs.writeFileSync(path.join(watchIconDir, 'icon-180.png'), png180);

const iosContentsJson = JSON.stringify({
  images: [
    {
      filename: "icon-120.png",
      idiom: "iphone",
      scale: "2x",
      size: "60x60"
    },
    {
      filename: "icon-180.png",
      idiom: "iphone",
      scale: "3x",
      size: "60x60"
    },
    {
      filename: "icon-1024.png",
      idiom: "ios-marketing",
      scale: "1x",
      size: "1024x1024"
    },
    {
      filename: "icon-1024.png",
      idiom: "universal",
      platform: "ios",
      size: "1024x1024"
    }
  ],
  info: {
    author: "xcode",
    version: 1
  }
}, null, 2);

const watchContentsJson = JSON.stringify({
  images: [
    {
      filename: "icon-1024.png",
      idiom: "watch-marketing",
      scale: "1x",
      size: "1024x1024"
    },
    {
      filename: "icon-1024.png",
      idiom: "universal",
      platform: "watchos",
      size: "1024x1024"
    },
    {
      filename: "icon-1024.png",
      idiom: "watch",
      scale: "2x",
      size: "1024x1024"
    }
  ],
  info: {
    author: "xcode",
    version: 1
  }
}, null, 2);

fs.writeFileSync(path.join(iosIconDir, 'Contents.json'), iosContentsJson);
fs.writeFileSync(path.join(watchIconDir, 'Contents.json'), watchContentsJson);

console.log("App Icons updated with universal & watch idioms!");
