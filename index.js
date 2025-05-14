const http = require('http');
const net = require('net');
const { Buffer } = require('buffer');
const { execSync } = require('child_process');
const { WebSocketServer, createWebSocketStream } = require('ws');

// --- Configuration (to be replaced by setup.sh or environment variables) ---
const UUID = process.env.UUID || 'YOUR_UUID_PLACEHOLDER'; // Modified by setup.sh
const SUB_PATH = process.env.SUB_PATH || 'YOUR_SUB_PATH_PLACEHOLDER'; // Modified by setup.sh
const NAME = process.env.NAME || 'YOUR_NAME_PLACEHOLDER'; // Modified by setup.sh
const PORT = process.env.PORT || 0; // Modified by setup.sh to a specific port
const DOMAIN = process.env.DOMAIN || 'YOUR_DOMAIN_PLACEHOLDER'; // Modified by setup.sh

let ISP = 'UnknownISP';
try {
  const metaInfo = execSync(
    'curl -s https://speed.cloudflare.com/meta | awk -F\\" \'{print $26"-"$18}\' | sed -e \'s/ /_/g\'',
    { encoding: 'utf-8', timeout: 5000 }
  );
  ISP = metaInfo.trim() || 'UnknownISP';
} catch (error) {
  console.warn(`Failed to fetch ISP info: ${error.message}`);
}

const VLESS_UUID_BYTES = Buffer.from(UUID.replace(/-/g, ''), 'hex');

function parseVlessHeader(msg) {
  if (msg.length < 24) return null;

  const version = msg[0];
  if (version !== 0x00) return null; // Only VLESS v0

  const receivedUUID = msg.slice(1, 17);
  if (!VLESS_UUID_BYTES.equals(receivedUUID)) return null;

  let offset = 17;
  const addonLength = msg[offset];
  offset += 1 + addonLength;

  offset += 1; // Skip Command byte

  const remotePort = msg.readUInt16BE(offset);
  offset += 2;

  const addressType = msg[offset];
  offset += 1;

  let remoteHost;
  switch (addressType) {
    case 0x01: // IPv4
      remoteHost = msg.slice(offset, offset + 4).join('.');
      offset += 4;
      break;
    case 0x02: // Domain name
      const hostLength = msg[offset];
      offset += 1;
      if (offset + hostLength > msg.length) return null;
      remoteHost = new TextDecoder().decode(msg.slice(offset, offset + hostLength));
      offset += hostLength;
      break;
    case 0x03: // IPv6
      remoteHost = msg.slice(offset, offset + 16)
        .reduce((s, b, i, a) => (i % 2 ? s.concat(a.slice(i - 1, i + 1)) : s), [])
        .map(b => b.readUInt16BE(0).toString(16))
        .join(':');
      offset += 16;
      break;
    default:
      return null;
  }

  return { remotePort, remoteHost, dataOffset: offset };
}

const httpServer = http.createServer((req, res) => {
  if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('VLESS Server is Running.\n');
  } else if (req.url === `/${SUB_PATH}`) {
    if (!DOMAIN) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Error: DOMAIN is not configured.\n');
      return;
    }
    const vlessURL = `vless://${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2F#${encodeURIComponent(NAME)}-${ISP}`;
    const base64Content = Buffer.from(vlessURL).toString('base64');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(base64Content + '\n');
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found.\n');
  }
});

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  ws.once('message', msg => {
    const headerInfo = parseVlessHeader(msg);
    if (!headerInfo) {
      ws.close(1008, 'Invalid VLESS header');
      return;
    }

    const { remotePort, remoteHost, dataOffset } = headerInfo;
    ws.send(Buffer.from([msg[0], 0])); // VLESS response

    const duplex = createWebSocketStream(ws);
    const remoteConnection = net.connect({ host: remoteHost, port: remotePort }, () => {
      if (msg.length > dataOffset) {
        remoteConnection.write(msg.slice(dataOffset));
      }
      duplex.pipe(remoteConnection).pipe(duplex);
    });

    remoteConnection.on('error', (err) => {
      // console.error(`Remote connection error to ${remoteHost}:${remotePort}: ${err.message}`);
      duplex.destroy();
      ws.close();
    });

    duplex.on('error', (err) => {
      // console.error(`WebSocket stream error: ${err.message}`);
      remoteConnection.destroy();
    });

    ws.on('close', () => {
      remoteConnection.destroy();
    });
  });

  ws.on('error', (err) => {
    // console.error(`WebSocket connection error: ${err.message}`);
    ws.close();
  });
});

httpServer.listen(PORT, () => {
  console.log(`VLESS server started on port ${PORT}`);
  console.log(`UUID: ${UUID}`);
  console.log(`Domain: ${DOMAIN}`);
  console.log(`Subscription Path: /${SUB_PATH}`);
  console.log(`Node Name Prefix: ${NAME}`);
});

wss.on('error', (err) => {
    console.error(`WebSocket Server critical error: ${err.message}`);
});
