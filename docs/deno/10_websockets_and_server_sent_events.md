# Module 10: WebSockets & Server-Sent Events

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Real-Time Communication

---

## Real-Time Communication: WebSockets vs SSE

Two protocols power real-time web communication, and they serve different use cases:

**WebSockets** establish a persistent **bidirectional** TCP connection. Both client and server can send messages at any time. Use WebSockets for: chat applications, collaborative editing, multiplayer games, live dashboards where the client also sends data.

**Server-Sent Events (SSE)** are a **server-to-client only** push channel built on top of regular HTTP. The client connects once and receives a stream of events. The browser has built-in reconnection logic. Use SSE for: live notifications, stock tickers, progress updates, log streaming — anywhere the client only needs to listen.

---

## WebSocket Server

Deno handles WebSocket upgrades natively using the `Deno.upgradeWebSocket()` function. When a client sends an HTTP Upgrade request, you call this function to switch the connection from HTTP to WebSocket protocol.

```typescript
// websocket_server.ts
Deno.serve({ port: 8080 }, (req: Request) => {
  const url = new URL(req.url);

  if (url.pathname === "/ws") {
    // Check if this is a WebSocket upgrade request
    if (req.headers.get("upgrade") !== "websocket") {
      return new Response("Expected WebSocket upgrade", { status: 400 });
    }

    const { socket, response } = Deno.upgradeWebSocket(req);

    socket.addEventListener("open", () => {
      console.log("Client connected");
      socket.send(JSON.stringify({ type: "welcome", message: "Connected to Deno WebSocket server" }));
    });

    socket.addEventListener("message", (event) => {
      console.log("Received:", event.data);

      try {
        const message = JSON.parse(event.data) as { type: string; data: unknown };
        // Echo back with server timestamp
        socket.send(JSON.stringify({
          type: "echo",
          original: message,
          serverTime: new Date().toISOString(),
        }));
      } catch {
        socket.send(JSON.stringify({ type: "error", message: "Invalid JSON" }));
      }
    });

    socket.addEventListener("close", (event) => {
      console.log(`Client disconnected: code=${event.code} reason=${event.reason}`);
    });

    socket.addEventListener("error", (event) => {
      console.error("WebSocket error:", event);
    });

    // Return the upgrade response — DO NOT return a regular Response
    return response;
  }

  return new Response("Not Found", { status: 404 });
});
```

---

## Multi-Client Chat Room with Deno KV Watch

This pattern uses KV Watch to broadcast messages to all connected clients without a separate pub/sub system:

```typescript
// chat_server.ts
interface ChatMessage {
  id: string;
  room: string;
  userId: string;
  username: string;
  text: string;
  timestamp: string;
}

const kv = await Deno.openKv();

// Track active connections per room (in-memory, per-process)
const rooms = new Map<string, Set<WebSocket>>();

function broadcast(roomId: string, data: unknown, exclude?: WebSocket): void {
  const clients = rooms.get(roomId);
  if (!clients) return;
  const message = JSON.stringify(data);
  for (const client of clients) {
    if (client !== exclude && client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  }
}

Deno.serve({ port: 8080 }, async (req: Request) => {
  const url = new URL(req.url);

  // WebSocket endpoint: /ws/chat/:roomId?userId=xxx&username=yyy
  const match = url.pathname.match(/^\/ws\/chat\/([^/]+)$/);
  if (match && req.headers.get("upgrade") === "websocket") {
    const roomId = match[1];
    const userId = url.searchParams.get("userId") ?? crypto.randomUUID();
    const username = url.searchParams.get("username") ?? `User${Math.floor(Math.random() * 1000)}`;

    const { socket, response } = Deno.upgradeWebSocket(req);

    // Add client to room
    if (!rooms.has(roomId)) rooms.set(roomId, new Set());
    rooms.get(roomId)!.add(socket);

    socket.addEventListener("open", () => {
      broadcast(roomId, {
        type: "user_joined",
        userId,
        username,
        timestamp: new Date().toISOString(),
      }, socket);

      socket.send(JSON.stringify({
        type: "joined",
        roomId,
        userId,
        username,
      }));
    });

    socket.addEventListener("message", async (event) => {
      let incoming: { text?: string };
      try {
        incoming = JSON.parse(event.data as string);
      } catch {
        return;
      }

      if (!incoming.text?.trim()) return;

      const message: ChatMessage = {
        id: crypto.randomUUID(),
        room: roomId,
        userId,
        username,
        text: incoming.text.slice(0, 2000),  // Limit message length
        timestamp: new Date().toISOString(),
      };

      // Persist to KV (last 100 messages per room)
      await kv.set(["messages", roomId, message.id], message, {
        expireIn: 7 * 24 * 60 * 60 * 1000,  // 7 days
      });

      // Broadcast to all clients in the room
      broadcast(roomId, { type: "message", ...message });
    });

    socket.addEventListener("close", () => {
      rooms.get(roomId)?.delete(socket);
      if (rooms.get(roomId)?.size === 0) rooms.delete(roomId);

      broadcast(roomId, {
        type: "user_left",
        userId,
        username,
        timestamp: new Date().toISOString(),
      });
    });

    return response;
  }

  // REST: Get recent messages for a room
  if (url.pathname.startsWith("/api/rooms/") && req.method === "GET") {
    const roomId = url.pathname.split("/")[3];
    const messages: ChatMessage[] = [];
    const iter = kv.list<ChatMessage>({ prefix: ["messages", roomId] }, { limit: 50, reverse: true });
    for await (const entry of iter) messages.push(entry.value);
    return Response.json(messages.reverse());
  }

  return new Response("Not Found", { status: 404 });
});
```

---

## WebSocket Client (Deno → External Service)

Deno's `WebSocket` constructor is the standard browser API — use it to connect to external WebSocket services:

```typescript
// websocket_client.ts — connect to an external WebSocket feed
async function connectToMarketFeed(symbols: string[]): Promise<void> {
  const ws = new WebSocket("wss://stream.example.com/market");

  ws.addEventListener("open", () => {
    console.log("Connected to market feed");
    // Subscribe to specific symbols
    ws.send(JSON.stringify({
      action: "subscribe",
      symbols,
    }));
  });

  ws.addEventListener("message", (event) => {
    const tick = JSON.parse(event.data as string) as {
      symbol: string;
      price: number;
      volume: number;
      timestamp: string;
    };
    console.log(`${tick.symbol}: $${tick.price} (vol: ${tick.volume})`);
  });

  ws.addEventListener("close", async (event) => {
    console.warn(`Disconnected: ${event.code} ${event.reason}. Reconnecting in 5s...`);
    await new Promise((r) => setTimeout(r, 5000));
    await connectToMarketFeed(symbols);  // Auto-reconnect
  });

  ws.addEventListener("error", (event) => {
    console.error("WebSocket error:", event);
  });

  // Keep the process alive while connected
  await new Promise<void>((resolve) => {
    ws.addEventListener("close", () => resolve());
  });
}

await connectToMarketFeed(["AAPL", "GOOGL", "MSFT"]);
```

---

## Server-Sent Events with Native `Deno.serve`

```typescript
// sse_server.ts
const kv = await Deno.openKv();

Deno.serve({ port: 8080 }, async (req: Request) => {
  const url = new URL(req.url);

  if (url.pathname.startsWith("/events/") && req.method === "GET") {
    const topic = url.pathname.slice("/events/".length);

    // Create a readable stream that sends SSE data
    let watcher: ReturnType<typeof kv.watch> | null = null;

    const stream = new ReadableStream({
      async start(controller) {
        const encoder = new TextEncoder();

        // Send initial connection event
        controller.enqueue(encoder.encode(`event: connected\ndata: {"topic":"${topic}"}\n\n`));

        // Watch for KV changes and stream them as SSE events
        watcher = kv.watch<[{ data: unknown; id: string }]>([["events", topic]]);

        try {
          for await (const [entry] of watcher) {
            if (entry.value === null) continue;

            const sseData = `id: ${entry.versionstamp}\nevent: update\ndata: ${JSON.stringify(entry.value.data)}\n\n`;
            controller.enqueue(encoder.encode(sseData));
          }
        } catch {
          // Client closed the connection
        } finally {
          controller.close();
        }
      },
      cancel() {
        // Client disconnected — stop the watcher
        watcher?.cancel();
      },
    });

    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",  // Disable NGINX buffering for SSE
      },
    });
  }

  // Publish an event to a topic
  if (url.pathname.startsWith("/publish/") && req.method === "POST") {
    const topic = url.pathname.slice("/publish/".length);
    const data = await req.json();
    await kv.set(["events", topic], { data, id: crypto.randomUUID() });
    return Response.json({ published: true });
  }

  return new Response("Not Found", { status: 404 });
});
```

**SSE with Hono** (using the `streamSSE` helper from Module 09):

```typescript
import { Hono } from "hono";
import { streamSSE } from "hono/streaming";

const app = new Hono();

app.get("/events/:topic", async (c) => {
  const topic = c.req.param("topic");
  const kv = await Deno.openKv();

  return streamSSE(c, async (stream) => {
    await stream.writeSSE({ event: "connected", data: JSON.stringify({ topic }) });

    const watcher = kv.watch<[{ data: unknown }]>([["events", topic]]);
    for await (const [entry] of watcher) {
      if (stream.closed) break;
      if (entry.value) {
        await stream.writeSSE({
          event: "update",
          data: JSON.stringify(entry.value.data),
          id: entry.versionstamp,
        });
      }
    }
  });
});

Deno.serve({ port: 8080 }, app.fetch);
```

---

## Testing WebSocket Connections

```typescript
// websocket_test.ts
Deno.test("WebSocket chat round-trip", async () => {
  // Start the server
  const server = Deno.serve({ port: 9999 }, handler);

  // Connect as a client
  const ws = new WebSocket("ws://localhost:9999/ws/chat/test-room?username=TestUser");

  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("timeout")), 5000);

    ws.addEventListener("message", (event) => {
      const msg = JSON.parse(event.data as string);
      if (msg.type === "joined") {
        clearTimeout(timeout);
        ws.close();
        resolve();
      }
    });

    ws.addEventListener("error", reject);
  });

  await server.shutdown();
});

function handler(req: Request): Response {
  return new Response("stub");  // replace with actual handler
}
```

---

## Troubleshooting

**WebSocket connection immediately closes with code 1006**

Code 1006 means the connection was closed abnormally without a proper close handshake. Common causes: server crashed on the handler, missing `--allow-net` permission, or the server returned a non-101 response. Check the server's error log.

**SSE stream stops updating after a few minutes**

Intermediate proxies (NGINX, AWS ALB) timeout idle HTTP connections. Add a keepalive ping every 30 seconds:

```typescript
const stream = new ReadableStream({
  async start(controller) {
    const encoder = new TextEncoder();
    const keepAlive = setInterval(() => {
      controller.enqueue(encoder.encode(": keepalive\n\n"));  // SSE comment
    }, 30_000);

    // ... watch loop

    clearInterval(keepAlive);
  },
});
```

**`Deno.upgradeWebSocket is not a function`**

This function requires Deno 1.12+. Older code used `std/ws` from the standard library — that package is deprecated. Upgrade Deno.
