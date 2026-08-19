# Module 04: Low-Level Network Systems — TCP Sockets, UDP Datagrams & DNS

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Network Engineering, TCP Framing & Socket Systems

---

## 1. Low-Level TCP Sockets (`node:net`)

Unlike HTTP (which is request-response), **TCP is a continuous bidirectional byte stream**.

```text
┌─────────────────────────────────────────────────────────────┐
│                 The Golden Law of TCP Networking            │
├─────────────────────────────────────────────────────────────┤
│ **TCP does NOT preserve message boundaries!**               │
│ - If you send two 100-byte JSON strings, the receiver might │
│   receive one 200-byte chunk, or ten 20-byte chunks!        │
│ - You MUST implement a **Framing Protocol**                 │
│   (Length-Prefixed or Delimiter-Based).                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Robust Length-Prefixed TCP Frame Parser

Let's build a production TCP server that handles message fragmentation and packet coalescing safely:

```javascript
// src/networking/tcp_server.js
import net from 'node:net';

export class LengthPrefixedTcpServer {
  constructor(port) {
    this.port = port;
    this.server = net.createServer(this._handleConnection.bind(this));
  }

  _handleConnection(socket) {
    console.log(`[TCP]: Client connected from ${socket.remoteAddress}:${socket.remotePort}`);

    // 1. Optimize Socket Performance:
    socket.setNoDelay(true); // Disables Nagle's algorithm for immediate packet dispatch!
    socket.setKeepAlive(true, 60000); // 60s Keep-Alive probe

    let buffer = Buffer.alloc(0);

    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);

      // 2. Parse frames: [4-Byte Length Header] + [Payload]
      while (buffer.length >= 4) {
        const messageLength = buffer.readUInt32BE(0);

        if (buffer.length < 4 + messageLength) {
          // Incomplete message; wait for remaining TCP chunks:
          break;
        }

        // Extract complete payload:
        const payload = buffer.subarray(4, 4 + messageLength).toString('utf8');
        buffer = buffer.subarray(4 + messageLength); // Advance buffer

        this._processMessage(socket, payload);
      }
    });

    socket.on('error', (err) => console.error('[TCP Socket Error]:', err.message));
    socket.on('close', () => console.log('[TCP]: Client disconnected.'));
  }

  _processMessage(socket, message) {
    console.log('[TCP Message Received]:', message);

    // Send Length-Prefixed Response:
    const responsePayload = Buffer.from(`ACK: ${message}`, 'utf8');
    const responseHeader = Buffer.alloc(4);
    responseHeader.writeUInt32BE(responsePayload.length, 0);

    socket.write(Buffer.concat([responseHeader, responsePayload]));
  }

  start() {
    this.server.listen(this.port, () => {
      console.log(`🚀 Low-Level TCP Server listening on port ${this.port}`);
    });
  }
}
```

---

## 3. High-Throughput UDP Datagrams (`node:dgram`)

**UDP (User Datagram Protocol)** is a connectionless, lightweight transport protocol. Packets are dispatched without handshake overhead, making UDP the standard for DNS, VoIP, and gaming telemetry:

```javascript
// src/networking/udp_telemetry.js
import dgram from 'node:dgram';

// 1. UDP Receiver Server:
export function startUdpServer(port = 5000) {
  const server = dgram.createSocket('udp4');

  server.on('message', (msg, rinfo) => {
    console.log(`[UDP From ${rinfo.address}:${rinfo.port}]: ${msg.toString()}`);
  });

  server.on('listening', () => {
    const address = server.address();
    console.log(`🚀 UDP Server listening on ${address.address}:${address.port}`);
  });

  server.bind(port);
  return server;
}

// 2. UDP Telemetry Dispatcher:
export function sendUdpMetric(host, port, metricPayload) {
  const client = dgram.createSocket('udp4');
  const message = Buffer.from(JSON.stringify(metricPayload));

  client.send(message, port, host, (err) => {
    client.close();
    if (err) console.error('[UDP Dispatch Error]:', err);
  });
}
```

---

## 4. DNS Resolution Architecture (`dns.lookup` vs `dns.resolve`)

```text
┌─────────────────────────────────────────────────────────────┐
│                 Node.js DNS Resolution Modes                │
├────────────────────┬────────────────────────────────────────┤
│ **`dns.lookup()`** │ Uses OS `getaddrinfo` (Synchronous C   │
│                    │ call on Libuv Thread Pool!).           │
│                    │ Respects `/etc/hosts`.                 │
├────────────────────┼────────────────────────────────────────┤
│ **`dns.resolve4()`**│ Uses **c-ares** asynchronous network  │
│                    │ socket queries.                        │
│                    │ Bypasses thread pool; 10x throughput!  │
└────────────────────┴────────────────────────────────────────┘
```

```javascript
import dns from 'node:dns/promises';

// Asynchronous DNS Service Discovery:
export async function resolveServiceEndpoints(hostname) {
  // Query SRV or A records asynchronously without thread pool contention:
  const ipAddresses = await dns.resolve4(hostname);
  console.log(`Resolved ${hostname} to IPs:`, ipAddresses);
  return ipAddresses;
}
```

---

## Troubleshooting & Best Practices

1. **Always Set `socket.setNoDelay(true)` for Low-Latency TCP**
   By default, the OS kernel enables Nagle's algorithm, buffering small packets for up to 40ms to maximize MTU packet density. Calling `setNoDelay(true)` forces immediate transmission.

2. **UDP Packet Size Limit (MTU)**
   Keep UDP datagram payloads below **1,472 bytes** (Standard Ethernet MTU 1500 - 20B IP header - 8B UDP header) to prevent IP fragmentation and packet drop rates across internet routers.
