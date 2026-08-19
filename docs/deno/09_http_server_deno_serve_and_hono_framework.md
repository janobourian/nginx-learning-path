# Module 09: HTTP Server — `Deno.serve` & Hono Framework

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Web Server & HTTP Framework

---

## Building HTTP Servers in Deno

Deno provides two ways to build HTTP servers. The first is `Deno.serve()` — the native built-in API that accepts a handler function following the Fetch API's `Request`/`Response` model. The second is using a framework on top of it, with **Hono** being the most widely adopted in the Deno ecosystem.

Both approaches use the same underlying Fetch API types that browsers use — the same `Request`, `Response`, `Headers`, and `URL` objects. This is the power of Deno's web standards approach: HTTP handler code looks the same whether it runs in a browser Service Worker, on Deno locally, or on Deno Deploy at the edge.

---

## `Deno.serve()` — The Native HTTP Server

```typescript
// server.ts
Deno.serve({
  port: 8080,
  hostname: "0.0.0.0",

  handler: async (request: Request): Promise<Response> => {
    const url = new URL(request.url);

    // Route matching
    if (request.method === "GET" && url.pathname === "/") {
      return new Response("Welcome to Deno!", {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      });
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({ status: "ok", timestamp: new Date().toISOString() });
    }

    if (request.method === "POST" && url.pathname === "/api/echo") {
      const body = await request.json();
      return Response.json({ received: body });
    }

    return new Response("Not Found", { status: 404 });
  },

  onListen({ port, hostname }) {
    console.log(`Listening on http://${hostname}:${port}`);
  },
});
```

```bash
deno run --allow-net server.ts
```

### Working with Request and Response

```typescript
async function handler(req: Request): Promise<Response> {
  // Reading request data
  const url = new URL(req.url);
  const method = req.method;
  const headers = Object.fromEntries(req.headers.entries());
  const query = Object.fromEntries(url.searchParams.entries());
  const contentType = req.headers.get("Content-Type") ?? "";

  // Read body based on content type
  let body: unknown = null;
  if (contentType.includes("application/json")) {
    body = await req.json();
  } else if (contentType.includes("application/x-www-form-urlencoded")) {
    const formData = await req.formData();
    body = Object.fromEntries(formData.entries());
  } else if (contentType.includes("text/")) {
    body = await req.text();
  }

  // Building responses
  // JSON response
  const jsonResponse = Response.json({ success: true, data: body }, { status: 200 });

  // HTML response
  const htmlResponse = new Response("<h1>Hello</h1>", {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });

  // Redirect
  const redirect = Response.redirect("https://example.com", 302);

  // File download
  const file = await Deno.open("./report.pdf");
  const fileResponse = new Response(file.readable, {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": "attachment; filename=report.pdf",
    },
  });

  // Streaming response
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const encoder = new TextEncoder();
      for (let i = 0; i < 5; i++) {
        await new Promise((resolve) => setTimeout(resolve, 500));
        controller.enqueue(encoder.encode(`data: ${i}\n\n`));
      }
      controller.close();
    },
  });
  const streamResponse = new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
    },
  });

  return jsonResponse;
}
```

---

## Hono — The Recommended Framework for Deno

Hono is a lightweight, ultrafast web framework that runs on Deno, Node.js, Bun, Cloudflare Workers, and browsers. It uses the same Request/Response types as `Deno.serve()` and adds routing, middleware, validation, and helpers.

```bash

# Add to deno.json imports
```

```json
{
  "imports": {
    "hono": "jsr:@hono/hono@^4",
    "@hono/zod-validator": "jsr:@hono/zod-validator@^0.4",
    "zod": "npm:zod@^3"
  }
}
```

### Basic Hono Application

```typescript
// src/main.ts
import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { prettyJSON } from "hono/pretty-json";
import { HTTPException } from "hono/http-exception";

const app = new Hono();

// Middleware
app.use("*", logger());
app.use("*", cors({
  origin: ["https://app.example.com", "http://localhost:3000"],
  allowMethods: ["GET", "POST", "PUT", "DELETE", "PATCH"],
  allowHeaders: ["Content-Type", "Authorization"],
}));
app.use("/api/*", prettyJSON());

// Routes
app.get("/", (c) => c.text("Deno + Hono API"));

app.get("/api/health", (c) => {
  return c.json({ status: "ok", uptime: Deno.osUptime() });
});

// Path parameters
app.get("/api/users/:id", async (c) => {
  const id = c.req.param("id");
  const kv = await Deno.openKv();
  const user = await kv.get<User>(["users", id]);
  if (!user.value) {
    throw new HTTPException(404, { message: `User ${id} not found` });
  }
  return c.json(user.value);
});

// Query parameters
app.get("/api/users", async (c) => {
  const page = Number(c.req.query("page") ?? "1");
  const limit = Math.min(Number(c.req.query("limit") ?? "20"), 100);
  // ... fetch from KV with pagination
  return c.json({ users: [], page, limit });
});

// Error handling
app.onError((err, c) => {
  if (err instanceof HTTPException) {
    return c.json({ error: err.message }, err.status);
  }
  console.error(err);
  return c.json({ error: "Internal server error" }, 500);
});

app.notFound((c) => c.json({ error: "Not found" }, 404));

Deno.serve({ port: 8080 }, app.fetch);

interface User { id: string; name: string; email: string; }
```

---

## Input Validation with Zod

```typescript
import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";

const app = new Hono();

// Define validation schemas
const CreateUserSchema = z.object({
  name: z.string().min(2).max(100),
  email: z.string().email(),
  age: z.number().int().min(18).max(120).optional(),
  role: z.enum(["user", "admin", "moderator"]).default("user"),
});

const UserQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().optional(),
});

// Validate JSON body
app.post("/api/users",
  zValidator("json", CreateUserSchema),
  async (c) => {
    const data = c.req.valid("json");  // TypeScript-typed, validated
    const kv = await Deno.openKv();
    const id = crypto.randomUUID();
    const user = { id, ...data, createdAt: new Date() };
    await kv.set(["users", id], user);
    return c.json(user, 201);
  }
);

// Validate query parameters
app.get("/api/users",
  zValidator("query", UserQuerySchema),
  async (c) => {
    const { page, limit, search } = c.req.valid("query");
    // ... use validated, typed, coerced params
    return c.json({ users: [], page, limit });
  }
);
```

---

## Middleware: Authentication, Rate Limiting

```typescript
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";

const app = new Hono();
const kv = await Deno.openKv();

// JWT authentication middleware
async function requireAuth(c: ReturnType<typeof app.createContext>, next: () => Promise<void>) {
  const authHeader = c.req.header("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new HTTPException(401, { message: "Missing or invalid Authorization header" });
  }

  const token = authHeader.slice(7);
  const session = await kv.get<{ userId: string; role: string }>(["sessions", token]);

  if (!session.value) {
    throw new HTTPException(401, { message: "Invalid or expired token" });
  }

  c.set("userId", session.value.userId);
  c.set("userRole", session.value.role);
  await next();
}

// Simple in-KV rate limiter middleware
function rateLimit(maxRequests: number, windowMs: number) {
  return async (c: { req: { header: (h: string) => string | undefined } }, next: () => Promise<void>) => {
    const ip = c.req.header("X-Real-IP") ?? "unknown";
    const window = Math.floor(Date.now() / windowMs);
    const key = ["rate_limit", ip, window];

    const entry = await kv.get<number>(key);
    const count = (entry.value ?? 0) + 1;

    if (count > maxRequests) {
      throw new HTTPException(429, { message: "Too many requests" });
    }

    await kv.set(key, count, { expireIn: windowMs });
    await next();
  };
}

// Apply middleware
app.use("/api/protected/*", requireAuth as never);
app.use("/api/*", rateLimit(100, 60_000) as never);  // 100 req/min per IP

app.get("/api/protected/profile", (c) => {
  return c.json({ userId: c.get("userId"), role: c.get("userRole") });
});
```

---

## Server-Sent Events (SSE)

```typescript
import { Hono } from "hono";
import { streamSSE } from "hono/streaming";

const app = new Hono();
const kv = await Deno.openKv();

app.get("/api/events/:topic", (c) => {
  const topic = c.req.param("topic");

  return streamSSE(c, async (stream) => {
    // Send initial connection confirmation
    await stream.writeSSE({ event: "connected", data: JSON.stringify({ topic }) });

    // Watch KV for changes and stream them to the client
    const watcher = kv.watch<[{ message: string; at: string }]>([["events", topic]]);

    try {
      for await (const [entry] of watcher) {
        if (entry.value === null) continue;
        await stream.writeSSE({
          event: "message",
          data: JSON.stringify(entry.value),
          id: entry.versionstamp,
        });
      }
    } catch {
      // Client disconnected
    }
  });
});

// Publish events (from another endpoint or worker)
app.post("/api/events/:topic", async (c) => {
  const topic = c.req.param("topic");
  const body = await c.req.json<{ message: string }>();
  await kv.set(["events", topic], { message: body.message, at: new Date().toISOString() });
  return c.json({ published: true });
});

Deno.serve({ port: 8080 }, app.fetch);
```

---

## Running and Testing the Server

```bash

# Development with watch mode (restart on file changes)
deno run --watch --allow-net --allow-env src/main.ts

# With all required permissions specified explicitly
deno run \
  --allow-net=0.0.0.0:8080 \
  --allow-env=PORT,DATABASE_URL \
  --allow-read=./public \
  src/main.ts

# Test endpoints with curl
curl http://localhost:8080/api/health
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice","email":"alice@example.com"}'

# Run HTTP integration tests
deno test --allow-net tests/http_test.ts
```

---

## Troubleshooting

### `Error: Deno.serve is not a function`

Requires Deno 1.35+. Run `deno upgrade` to get the latest version.

### Hono routes not matching for paths with trailing slashes

By default Hono is strict about trailing slashes. Use `app.get("/api/users/", ...)` alongside `app.get("/api/users", ...)` or configure the router to be lenient. Alternatively, add middleware that normalizes trailing slashes.

### CORS preflight returning 404

Hono's `cors()` middleware handles OPTIONS automatically only for paths that have other method handlers. Add an explicit OPTIONS handler or ensure `cors()` middleware is applied before route definitions with `app.use("*", cors(...))`.
