# Module 10: Real-Time WebSockets, Socket.IO & Server-Sent Events (SSE)

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Real-Time Protocols, WebSockets & Server-Sent Events

---

## 1. Real-Time Protocol Decision Matrix

Modern web architectures require choosing the right communication protocol for the use case:

| Protocol | Directionality | Transport Layer | Auto-Reconnect | Best Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **WebSockets (`ws`)** | **Full-Duplex (Bidirectional)** | Custom TCP WebSocket protocol | Manual / Application layer | Chat apps, multiplayer gaming, collaborative whiteboards, live trading desks |
| **Server-Sent Events (SSE)** | **Unidirectional (Server ──► Client)** | **Standard HTTP / HTTP/2 (`text/event-stream`)** | **Built-in to browser `EventSource`!** | LLM token streaming (ChatGPT-style), stock tickers, system telemetry dashboards |
| **HTTP Long-Polling** | Request-Response simulation | Standard HTTP | Client-driven | Legacy fallback only |

---

## 2. High-Performance WebSockets with `package:ws`

The **`ws`** package is the fastest, standard WebSocket implementation for Node.js:

```bash
npm install ws
```

### 1. Robust WebSocket Server with Heartbeat Dead-Connection Detection

Over time, mobile devices lose WiFi or drop into cellular dead zones without sending a TCP close frame (creating "Zombie Connections" that exhaust server file descriptors).

Use a **Ping/Pong Heartbeat** to detect and terminate zombie sockets:

```javascript
// src/realtime/websocket_server.js
import { WebSocketServer, WebSocket } from 'ws';
import http from 'node:http';

const server = http.createServer();
const wss = new WebSocketServer({ server });

// Heartbeat tracking:
function heartbeat() {
  this.isAlive = true;
}

wss.on('connection', (ws, req) => {
  ws.isAlive = true;
  ws.on('pong', heartbeat);

  const clientIp = req.socket.remoteAddress;
  console.log(`[WebSocket]: Client connected from ${clientIp}. Total: ${wss.clients.size}`);

  ws.on('message', (data, isBinary) => {
    const messageString = isBinary ? data : data.toString();
    console.log('[WebSocket Message]:', messageString);

    // Broadcast message to all connected clients:
    wss.clients.forEach((client) => {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(data, { binary: isBinary });
      }
    });
  });

  ws.on('close', () => {
    console.log(`[WebSocket]: Client disconnected. Remaining: ${wss.clients.size}`);
  });
});

// Periodic Ping Interval (Runs every 30 seconds):
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      console.log('[WebSocket]: Terminating unresponsive zombie socket.');
      return ws.terminate(); // Force close dead connection
    }

    ws.isAlive = false;
    ws.ping(); // Client will reply with pong
  });
}, 30000);

wss.on('close', () => {
  clearInterval(pingInterval);
});

server.listen(8080, () => {
  console.log('🚀 WebSocket Server listening on ws://localhost:8080');
});
```

---

## 3. Scaling WebSockets Horizontally with Redis Pub/Sub

When scaling across 10 Kubernetes Pods, a client connected to Pod A cannot send a WebSocket message to a client connected to Pod B directly.

Use **Redis Pub/Sub** as a global message bus:

```text
Horizontal WebSocket Scaling with Redis:
[Client 1] ──► [Node.js Pod A] ──► [Redis Channel: "chat:global"]
                                            │
                                            ▼ (Redis Pub/Sub Broadcast)
[Client 2] ◄── [Node.js Pod B] ◄────────────┘
```

```javascript
// src/realtime/distributed_socket.js
import { WebSocketServer, WebSocket } from 'ws';
import Redis from 'ioredis';

const redisPublisher = new Redis(process.env.REDIS_URL);
const redisSubscriber = new Redis(process.env.REDIS_URL);

const wss = new WebSocketServer({ port: 8081 });

// Subscribe to global Redis channel:
redisSubscriber.subscribe('chat:broadcast');

redisSubscriber.on('message', (channel, message) => {
  // Broadcast Redis message to all local clients connected to this specific Node Pod:
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
});

wss.on('connection', (ws) => {
  ws.on('message', (data) => {
    // Publish message to Redis so ALL pods receive it:
    redisPublisher.publish('chat:broadcast', data.toString());
  });
});
```

---

## 4. Server-Sent Events (SSE) for LLM Streaming & Telemetry

Server-Sent Events run over standard HTTP and require **zero external dependencies**:

```javascript
// src/realtime/sse_server.js
import http from 'node:http';

const server = http.createServer((req, res) => {
  if (req.url === '/api/events' && req.method === 'GET') {
    // 1. Establish SSE HTTP Headers:
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });

    // 2. Initial Handshake Message:
    res.write('event: connected\ndata: {"status":"streaming_ready"}\n\n');

    let eventId = 0;

    // 3. Emit real-time telemetry events every second:
    const timer = setInterval(() => {
      eventId++;
      const payload = JSON.stringify({
        id: eventId,
        cpuUsage: (Math.random() * 100).toFixed(2),
        timestamp: new Date().toISOString(),
      });

      // SSE Protocol format: "id: <id>\nevent: <name>\ndata: <payload>\n\n"
      res.write(`id: ${eventId}\nevent: metric_update\ndata: ${payload}\n\n`);
    }, 1000);

    // Clean up timer on client disconnect:
    req.on('close', () => {
      clearInterval(timer);
      console.log('SSE Client disconnected.');
    });
    return;
  }

  res.writeHead(404);
  res.end('Not Found');
});

server.listen(3000, () => {
  console.log('SSE Stream available at http://localhost:3000/api/events');
});
```

---

## Troubleshooting & Best Practices

1. **Reverse Proxy Buffering with SSE & WebSockets**
   When placing NGINX in front of SSE or WebSockets, NGINX may buffer SSE chunks by default. Always configure `X-Accel-Buffering: no` in HTTP headers or `proxy_buffering off;` in NGINX.

2. **WebSocket Upgrade Handshake Authentication**
   Never validate authentication tokens *after* establishing a WebSocket connection. Validate the JWT token during the initial HTTP Upgrade handshake (`server.on('upgrade', (req, socket, head) => ...)`), rejecting unauthorized requests before allocating WebSocket memory.
