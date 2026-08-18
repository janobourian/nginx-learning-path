# Module 19: Production Patterns — Performance, Observability & Edge Architecture

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Production Engineering & Systems Design

---

## Deno in Production: Architecture Overview

Building production services with Deno requires the same engineering discipline as any other runtime: careful observability, graceful shutdown, connection pooling, structured logging, and circuit-breaking for external dependencies. This module assembles all previous concepts into production-ready patterns.

---

## Structured JSON Logging

Replace `console.log` with a structured logger that outputs JSON for log aggregation systems (Datadog, Loki, Cloud Logging):

```typescript
// logger.ts
type LogLevel = "debug" | "info" | "warn" | "error";

interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: string;
  service: string;
  version: string;
  requestId?: string;
  userId?: string;
  duration?: number;
  error?: string;
  stack?: string;
  [key: string]: unknown;
}

const SERVICE_NAME = Deno.env.get("SERVICE_NAME") ?? "api";
const VERSION = Deno.env.get("APP_VERSION") ?? "unknown";
const LOG_LEVEL = (Deno.env.get("LOG_LEVEL") ?? "info") as LogLevel;

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0, info: 1, warn: 2, error: 3,
};

function shouldLog(level: LogLevel): boolean {
  return LEVEL_ORDER[level] >= LEVEL_ORDER[LOG_LEVEL];
}

function log(level: LogLevel, message: string, context: Record<string, unknown> = {}): void {
  if (!shouldLog(level)) return;

  const entry: LogEntry = {
    level,
    message,
    timestamp: new Date().toISOString(),
    service: SERVICE_NAME,
    version: VERSION,
    ...context,
  };

  const output = JSON.stringify(entry);
  if (level === "error") {
    console.error(output);
  } else {
    console.log(output);
  }
}

export const logger = {
  debug: (message: string, ctx?: Record<string, unknown>) => log("debug", message, ctx),
  info:  (message: string, ctx?: Record<string, unknown>) => log("info",  message, ctx),
  warn:  (message: string, ctx?: Record<string, unknown>) => log("warn",  message, ctx),
  error: (message: string, error?: unknown, ctx?: Record<string, unknown>) => {
    const errorCtx: Record<string, unknown> = { ...ctx };
    if (error instanceof Error) {
      errorCtx.error = error.message;
      errorCtx.stack = error.stack;
    }
    log("error", message, errorCtx);
  },
};
```

Usage:
```typescript
import { logger } from "./logger.ts";

logger.info("Server started", { port: 8080, env: "production" });
logger.warn("Database connection slow", { latencyMs: 450, query: "SELECT..." });
logger.error("Failed to process payment", paymentError, { orderId: "ord_123" });
```

---

## Request Tracing Middleware

```typescript
// middleware/tracing.ts
import { type MiddlewareHandler } from "hono";
import { logger } from "../logger.ts";

export const tracingMiddleware: MiddlewareHandler = async (c, next) => {
  const requestId = c.req.header("X-Request-Id") ?? crypto.randomUUID();
  const start = performance.now();

  // Make request ID available to all downstream handlers
  c.set("requestId", requestId);

  // Return request ID in response so clients can correlate
  c.header("X-Request-Id", requestId);

  try {
    await next();
  } catch (error) {
    logger.error("Unhandled request error", error, {
      requestId,
      method: c.req.method,
      path: c.req.path,
    });
    throw error;
  } finally {
    const duration = Math.round(performance.now() - start);
    const status = c.res.status;

    logger.info("Request completed", {
      requestId,
      method: c.req.method,
      path: c.req.path,
      status,
      duration,
      userAgent: c.req.header("User-Agent"),
      ip: c.req.header("X-Real-IP") ?? c.req.header("X-Forwarded-For"),
    });
  }
};
```

---

## Circuit Breaker Pattern

External services fail. A circuit breaker prevents a failing dependency from cascading into your service:

```typescript
// circuit_breaker.ts
type CircuitState = "CLOSED" | "OPEN" | "HALF_OPEN";

interface CircuitBreakerOptions {
  failureThreshold: number;    // Open after this many consecutive failures
  recoveryTimeout: number;     // ms to wait before trying again (HALF_OPEN)
  successThreshold: number;    // Successes in HALF_OPEN before closing
}

export class CircuitBreaker {
  private state: CircuitState = "CLOSED";
  private failureCount = 0;
  private successCount = 0;
  private lastFailureTime = 0;

  constructor(
    private readonly name: string,
    private readonly options: CircuitBreakerOptions,
  ) {}

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === "OPEN") {
      if (Date.now() - this.lastFailureTime > this.options.recoveryTimeout) {
        this.state = "HALF_OPEN";
        this.successCount = 0;
      } else {
        throw new Error(`Circuit breaker OPEN for ${this.name}: service unavailable`);
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess(): void {
    if (this.state === "HALF_OPEN") {
      this.successCount++;
      if (this.successCount >= this.options.successThreshold) {
        this.state = "CLOSED";
        this.failureCount = 0;
      }
    } else {
      this.failureCount = 0;  // Reset on success in CLOSED state
    }
  }

  private onFailure(): void {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.failureCount >= this.options.failureThreshold || this.state === "HALF_OPEN") {
      this.state = "OPEN";
      logger.warn(`Circuit breaker opened for ${this.name}`, {
        failureCount: this.failureCount,
      });
    }
  }

  getState(): CircuitState { return this.state; }
}

// Usage
import { logger } from "./logger.ts";

const paymentCircuit = new CircuitBreaker("payment-service", {
  failureThreshold: 5,
  recoveryTimeout: 30_000,  // 30 seconds
  successThreshold: 2,
});

async function processPayment(orderId: string): Promise<{ success: boolean }> {
  return await paymentCircuit.execute(async () => {
    const response = await fetch("https://payment-service.internal/process", {
      method: "POST",
      body: JSON.stringify({ orderId }),
    });
    if (!response.ok) throw new Error(`Payment service error: ${response.status}`);
    return response.json();
  });
}
```

---

## Health Check Endpoint

A comprehensive health check gives load balancers and orchestration systems the information they need to route traffic correctly:

```typescript
// health.ts
interface HealthStatus {
  status: "healthy" | "degraded" | "unhealthy";
  checks: Record<string, { status: "ok" | "error"; latencyMs?: number; error?: string }>;
  version: string;
  uptime: number;
}

export async function checkHealth(pool: Pool, redis: Redis): Promise<HealthStatus> {
  const checks: HealthStatus["checks"] = {};
  let overallStatus: HealthStatus["status"] = "healthy";

  // Check PostgreSQL
  const pgStart = performance.now();
  try {
    const client = await pool.connect();
    await client.queryObject("SELECT 1");
    client.release();
    checks.postgres = { status: "ok", latencyMs: Math.round(performance.now() - pgStart) };
  } catch (error) {
    checks.postgres = { status: "error", error: error instanceof Error ? error.message : "Unknown" };
    overallStatus = "unhealthy";
  }

  // Check Redis
  const redisStart = performance.now();
  try {
    await redis.ping();
    checks.redis = { status: "ok", latencyMs: Math.round(performance.now() - redisStart) };
  } catch (error) {
    checks.redis = { status: "error", error: error instanceof Error ? error.message : "Unknown" };
    if (overallStatus !== "unhealthy") overallStatus = "degraded";
  }

  return {
    status: overallStatus,
    checks,
    version: Deno.env.get("APP_VERSION") ?? "unknown",
    uptime: Math.round(performance.now() / 1000),
  };
}

// In your Hono app:
app.get("/health", async (c) => {
  const health = await checkHealth(pool, redis);
  const httpStatus = health.status === "healthy" ? 200
    : health.status === "degraded" ? 200
    : 503;
  return c.json(health, httpStatus);
});

// Kubernetes liveness probe (just checks the process is alive)
app.get("/livez", (c) => c.json({ alive: true }));

// Kubernetes readiness probe (checks if ready to serve traffic)
app.get("/readyz", async (c) => {
  const health = await checkHealth(pool, redis);
  if (health.status === "unhealthy") return c.json({ ready: false }, 503);
  return c.json({ ready: true });
});

// Stub types for the example
declare class Pool { connect(): Promise<{ queryObject(s: string): Promise<void>; release(): void; }>; }
declare class Redis { ping(): Promise<void>; }
declare const pool: Pool;
declare const redis: Redis;
declare const app: import("hono").Hono;
```

---

## Memory and Performance Monitoring

```typescript
// monitoring.ts — periodically report runtime metrics
async function startMetricsReporter(intervalMs = 60_000): Promise<void> {
  const kv = await Deno.openKv();

  setInterval(async () => {
    const mem = Deno.memoryUsage();
    const cpu = Deno.cpuUsage();

    const metrics = {
      timestamp: new Date().toISOString(),
      memory: {
        heapUsedMB: Math.round(mem.heapUsed / 1024 / 1024),
        heapTotalMB: Math.round(mem.heapTotal / 1024 / 1024),
        externalMB: Math.round(mem.external / 1024 / 1024),
        rssMB: Math.round(mem.rss / 1024 / 1024),
      },
      cpu: {
        userMicros: cpu.user,
        systemMicros: cpu.system,
      },
    };

    logger.debug("Process metrics", metrics);

    // Store recent metrics in KV for the /metrics endpoint
    await kv.set(["metrics", "latest"], metrics, { expireIn: 5 * 60 * 1000 });
  }, intervalMs);
}

// Expose metrics endpoint
app.get("/metrics", async (c) => {
  const kv = await Deno.openKv();
  const latest = await kv.get(["metrics", "latest"]);
  return c.json(latest.value ?? { error: "No metrics collected yet" });
});
```

---

## Complete Production Application Entry Point

```typescript
// src/main.ts — production entry point
import { Hono } from "hono";
import { logger } from "./logger.ts";
import { tracingMiddleware } from "./middleware/tracing.ts";
import { userRoutes } from "./routes/users.ts";
import { checkHealth } from "./health.ts";
import { Pool } from "@db/postgres";

const PORT = Number(Deno.env.get("PORT") ?? "8080");
const DATABASE_URL = Deno.env.get("DATABASE_URL");

if (!DATABASE_URL) {
  logger.error("DATABASE_URL environment variable is required");
  Deno.exit(1);
}

// Initialize connection pool
const pool = new Pool(DATABASE_URL, 20);

const app = new Hono();

// Global middleware
app.use("*", tracingMiddleware);

// Routes
app.route("/api", userRoutes(pool));

// Health checks
app.get("/health", async (c) => {
  const health = await checkHealth(pool);
  return c.json(health, health.status === "unhealthy" ? 503 : 200);
});

// Graceful shutdown
let isShuttingDown = false;

const server = Deno.serve({
  port: PORT,
  onListen({ hostname, port }) {
    logger.info("Server started", { hostname, port, env: Deno.env.get("NODE_ENV") ?? "production" });
  },
}, async (req) => {
  if (isShuttingDown) {
    return new Response("Service Unavailable", { status: 503, headers: { "Retry-After": "10" } });
  }
  return app.fetch(req);
});

async function shutdown(signal: string): Promise<void> {
  logger.info("Shutting down", { signal });
  isShuttingDown = true;
  await new Promise((r) => setTimeout(r, 5000));  // Allow in-flight requests to complete
  server.shutdown();
  pool.end();
  logger.info("Shutdown complete");
  Deno.exit(0);
}

Deno.addSignalListener("SIGTERM", () => shutdown("SIGTERM"));
Deno.addSignalListener("SIGINT",  () => shutdown("SIGINT"));

// Stub for health check
async function checkHealth(_pool: Pool): Promise<{ status: "healthy" | "unhealthy" }> {
  return { status: "healthy" };
}

function userRoutes(_pool: Pool): Hono {
  return new Hono();
}
```

---

## Troubleshooting

**Memory usage grows indefinitely (memory leak)**

Check for unbounded caches, event listeners not removed, and circular references keeping objects alive. Use `Deno.memoryUsage()` tracked over time to confirm the trend. Common culprits in Deno: `kv.watch()` iterators not cancelled when clients disconnect, `setInterval` handlers accumulating state, and large arrays retained in module scope.

**p99 latency spikes periodically**

V8's garbage collector causes periodic pauses, especially when heap grows large. If your service creates many short-lived objects per request, GC pressure is high. Reduce allocation by reusing buffers and response objects. Monitor `heapUsed/heapTotal` ratio — when it consistently exceeds 80%, GC runs more aggressively.

**Graceful shutdown takes too long**

If `server.shutdown()` hangs, there are WebSocket or SSE connections keeping the server alive indefinitely. Track all long-lived connections and close them explicitly in the shutdown handler before calling `server.shutdown()`.
