# Module 08: Real-Time Event Streaming — WebSockets, SSE & Distributed Rooms

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Real-Time Architecture, WebSockets & Distributed Message Broadcasting

---

## 1. Real-Time Protocol Spectrum

```text
┌─────────────────────────────────────────────────────────────┐
│                 Real-Time Protocol Comparison               │
├────────────────────┬────────────────────────────────────────┤
│ **WebSockets**     │ **Bidirectional Full-Duplex**          │
│                    │ - Binary frames & text.                │
│                    │ - Collaborative editing, gaming, chat. │
├────────────────────┼────────────────────────────────────────┤
│ **SSE** (Server-   │ **Unidirectional (Server ──► Client)** │
│    **Sent Events** │ - Standard HTTP/2 stream.              │
│                    │ - Native browser reconnect; LLM tokens.│
├────────────────────┼────────────────────────────────────────┤
│ **WebTransport**   │ **Next-Gen WebRTC / QUIC Alternative** │
│                    │ - Multiplexed bidirectional UDP streams│
│                    │   with low-latency datagrams.          │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Enterprise Multi-Room WebSocket Manager

```javascript
// src/realtime/room_manager.js
import { WebSocketServer, WebSocket } from 'ws';

export class EnterpriseRoomManager {
  constructor(server) {
    this.wss = new WebSocketServer({ server });
    this.rooms = new Map(); // Map<roomId, Set<WebSocket>>

    this._init();
  }

  _init() {
    this.wss.on('connection', (ws, req) => {
      ws.isAlive = true;
      ws.currentRooms = new Set();

      ws.on('pong', () => (ws.isAlive = true));

      ws.on('message', (raw) => {
        try {
          const { action, room, payload } = JSON.parse(raw);
          this._handleAction(ws, action, room, payload);
        } catch (err) {
          ws.send(JSON.stringify({ error: 'Invalid JSON payload format' }));
        }
      });

      ws.on('close', () => this._handleDisconnect(ws));
    });

    // Zombie Connection Cleaner (Runs every 30s):
    setInterval(() => {
      this.wss.clients.forEach((ws) => {
        if (!ws.isAlive) return ws.terminate();
        ws.isAlive = false;
        ws.ping();
      });
    }, 30000);
  }

  _handleAction(ws, action, room, payload) {
    switch (action) {
      case 'JOIN':
        if (!this.rooms.has(room)) this.rooms.set(room, new Set());
        this.rooms.get(room).add(ws);
        ws.currentRooms.add(room);
        console.log(`[WebSocket]: Client joined room '${room}'`);
        break;

      case 'LEAVE':
        this.rooms.get(room)?.delete(ws);
        ws.currentRooms.delete(room);
        break;

      case 'BROADCAST':
        this.broadcastToRoom(room, payload, ws); // Exclude sender
        break;
    }
  }

  broadcastToRoom(room, message, senderWs = null) {
    const clients = this.rooms.get(room);
    if (!clients) return;

    const data = JSON.stringify({ room, data: message, timestamp: Date.now() });

    for (const client of clients) {
      if (client !== senderWs && client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    }
  }

  _handleDisconnect(ws) {
    for (const room of ws.currentRooms) {
      this.rooms.get(room)?.delete(ws);
    }
    ws.currentRooms.clear();
  }
}
```

---

## 3. Distributed WebSocket Scaling with Redis Streams

In a distributed Kubernetes deployment with 10 backend pods, use **Redis Streams** with consumer groups to process and broadcast messages across all pods:

```javascript
// src/realtime/distributed_stream_broker.js
import Redis from 'ioredis';

const redisClient = new Redis(process.env.REDIS_URL);
const STREAM_KEY = 'events:realtime';

// 1. Publish Event to Redis Stream:
export async function publishDistributedEvent(room, action, payload) {
  await redisClient.xadd(
    STREAM_KEY,
    '*', // Auto-generated timestamp ID
    'room', room,
    'action', action,
    'payload', JSON.stringify(payload)
  );
}

// 2. Consume Stream Across Microservice Pods:
export async function listenToDistributedStream(roomManager) {
  let lastId = '$'; // Listen for new incoming messages only

  while (true) {
    // Blocking read with 5-second timeout:
    const streams = await redisClient.xread('BLOCK', 5000, 'STREAMS', STREAM_KEY, lastId);

    if (streams) {
      const [key, entries] = streams[0];

      for (const [id, fields] of entries) {
        lastId = id;
        const room = fields[1];
        const action = fields[3];
        const payload = JSON.parse(fields[5]);

        // Broadcast to all local WebSocket connections in this room:
        roomManager.broadcastToRoom(room, payload);
      }
    }
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Implement Heartbeat Pings**
   Dead TCP connections caused by mobile signal loss or sleep mode will remain open in server memory forever unless terminated by a ping/pong interval.

2. **Authenticate During the HTTP Upgrade Handshake**
   Validate auth tokens before accepting the WebSocket connection. Refusing connections during `server.on('upgrade')` saves server RAM and CPU from malicious connections.
