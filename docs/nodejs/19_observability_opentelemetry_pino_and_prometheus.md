# Module 19: Observability: OpenTelemetry, Pino & Prometheus Metrics

**Track:** Node.js Enterprise Backend & Runtime  
**Directory:** `docs/nodejs/`  
**File:** `19_observability_opentelemetry_pino_and_prometheus.md`  
**Category:** Observability, Distributed Tracing & Telemetry Architecture  
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. High-Level Overview & Architectural Foundations

Operating mission-critical Node.js services at scale requires complete, unified observability across the three foundational telemetry pillars: **Structured Logs**, **Time-Series Metrics**, and **Distributed Traces**.

In high-throughput systems, poorly designed telemetry introduces severe performance overhead:
1. **Synchronous `console.log()`**: `console.log()` is synchronous when writing to POSIX pipes or files, blocking the Libuv event loop and dropping throughput by up to **80%**.
2. **Pino (Extreme Performance Logger)**: Writes non-blocking structured JSON logs using flat object serializers and dedicated background worker threads (`pino/file`), achieving 100,000+ logs/sec with 0% event loop lag.
3. **OpenTelemetry (OTel) & Prometheus**: Standardizes W3C Distributed Trace Context (`traceparent`) and Prometheus metrics (`prom-client`), correlating distributed spans across microservice boundaries.

```
+-------------------------------------------------------------------------------+
|                       Unified Node.js Observability Pipeline                  |
+-------------------------------------------------------------------------------+

  [ Inbound Request with W3C 'traceparent' Header ]
                         |
                         v
  [ OpenTelemetry Tracer (SDK) ] --------> Context Injection via AsyncLocalStorage
                         |
                         v
     [ Pino High-Speed Logger ] ---------> JSON Logs with correlated TraceId & SpanId
                         |                 (Non-blocking write via sonic-boom)
                         v
    [ Prometheus Client Metrics ] -------> HTTP Request Duration Histogram
                         |                 (Exposes /metrics scrape target)
                         v
  [ Upstream Exporters: Jaeger / Datadog / Prometheus / Grafana Loki ]
```

---

## 2. Complete Observability & Telemetry API Dictionary

Below is the complete API dictionary for OpenTelemetry, Pino, and Prometheus in Node.js:

| Class / Method | Module | Signature | Operational Execution Semantics |
| :--- | :--- | :--- | :--- |
| `pino([options], [destination])`| `pino` | `pino(opts?, dest?): Logger` | Instantiates ultra-fast structured JSON logger with level thresholds. |
| `logger.child(bindings)` | `pino` | `logger.child(bindings: object): Logger` | Creates contextual child logger injecting persistent metadata (e.g. `traceId`). |
| `new Counter(config)` | `prom-client` | `new Counter(opts): Counter` | Cumulative time-series metric that only increases (e.g., total requests, errors). |
| `new Gauge(config)` | `prom-client` | `new Gauge(opts): Gauge` | Metric that can arbitrarily increase or decrease (e.g., active memory, pool size). |
| `new Histogram(config)` | `prom-client` | `new Histogram(opts): Histogram` | Samples observations (request durations) into configurable bucket distributions. |
| `register.metrics()` | `prom-client` | `await register.metrics(): Promise<string>` | Generates Prometheus text-format scrape exposition payload for `/metrics`. |
| `collectDefaultMetrics()` | `prom-client` | `collectDefaultMetrics(opts?): void` | Automatically scrapes OS and V8 metrics (CPU, Heap, GC, Event Loop Lag). |
| `tracer.startActiveSpan(name, fn)`| `@opentelemetry/api`| `tracer.startActiveSpan(name, fn): Promise<T>` | Starts an active distributed trace span propagating context across async hops. |
| `span.setAttribute(key, value)`| `@opentelemetry/api`| `span.setAttribute(k: string, v: any): this` | Attaches diagnostic key-value attributes (e.g. `http.status_code`, `db.query`). |
| `span.end()` | `@opentelemetry/api`| `span.end(): void` | Closes span, recording end timestamp and dispatching to batch span processor. |

---

## 3. Technical Deep Dive: Non-Blocking Logging with Pino & Sonic-Boom

Standard `console.log()` calls invoke synchronous C++ write syscalls (`write(1, buf, len)` on file descriptor 1). If the operating system terminal or output pipe is saturated, `console.log()` blocks the JavaScript call stack, freezing all concurrent network connections.

### Pino Architecture:
* **Flat Fast Serialization**: Formats log JSON using pre-compiled string builders without dynamic object key reflection.
* **`sonic-boom`**: Offloads disk writes to dedicated off-thread binary buffers, automatically flushing on Libuv tick boundaries.
* **Result**: Up to **$5\times$ faster than Winston** and **$10\times$ faster than Bunyan**.

```
[ JavaScript Main Thread ]
            |
            v
  [ logger.info({ traceId }, "Message") ]  ====>  Flat string format in memory
            |
            v
   [ sonic-boom Ring Buffer (4KB Slab) ]  ====>  0ms main thread blocking!
            |
            v  (Asynchronously flushed by background thread)
     [ POSIX stdout fd: 1 ]
```

---

## 4. Hands-On Step-by-Step Production Lab: Unified Telemetry Engine (OTel + Pino + Prometheus)

This production lab implements a complete, enterprise-grade observability engine combining W3C distributed trace context propagation, structured Pino logging with trace injection, and Prometheus metrics collection.

### File 1: `src/observability_engine.ts`
```typescript
import pino from 'pino';
import client from 'prom-client';
import http from 'node:http';
import { AsyncLocalStorage } from 'node:async_hooks';
import crypto from 'node:crypto';
import { performance } from 'node:perf_hooks';

// 1. Asynchronous Context Propagation for Distributed Tracing
interface TraceContext {
    traceId: string;
    spanId: string;
}
export const traceStorage = new AsyncLocalStorage<TraceContext>();

// 2. High-Speed Pino Logger with Context Hook
export const logger = pino({
    level: process.env.LOG_LEVEL || 'info',
    mixin() {
        const context = traceStorage.getStore();
        return context ? { traceId: context.traceId, spanId: context.spanId } : {};
    },
    formatters: {
        level(label) {
            return { level: label.toUpperCase() };
        }
    },
    timestamp: pino.stdTimeFunctions.isoTime
});

// 3. Prometheus Metrics Setup
export const prometheusRegistry = new client.Registry();

// Enable default Node.js and V8 metrics (Event Loop Lag, GC, Memory)
client.collectDefaultMetrics({ register: prometheusRegistry, prefix: 'node_' });

// Custom Application Metrics
export const httpRequestDurationHistogram = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [prometheusRegistry]
});

export const activeRequestsGauge = new client.Gauge({
    name: 'http_active_requests_total',
    help: 'Number of currently active HTTP requests in flight',
    registers: [prometheusRegistry]
});

// 4. Observable Production HTTP Service
export class ObservableHttpServer {
    private server: http.Server;

    constructor(private readonly port: number) {
        this.server = http.createServer((req, res) => this.handleRequest(req, res));
    }

    private async handleRequest(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
        // Extract W3C Traceparent or generate fresh Trace ID
        const traceparent = req.headers['traceparent'] as string;
        const traceId = traceparent ? traceparent.split('-')[1] : crypto.randomBytes(16).toString('hex');
        const spanId = crypto.randomBytes(8).toString('hex');

        // Run entire request within AsyncLocalStorage trace context
        await traceStorage.run({ traceId, spanId }, async () => {
            activeRequestsGauge.inc();
            const startTime = performance.now();
            const url = req.url || '/';
            const method = req.method || 'GET';

            logger.info({ url, method }, 'Inbound request received');

            // Prometheus Metrics Endpoint
            if (url === '/metrics') {
                const metricsOutput = await prometheusRegistry.metrics();
                res.writeHead(200, { 'Content-Type': client.register.contentType });
                res.end(metricsOutput);
                activeRequestsGauge.dec();
                return;
            }

            // Application API Workload
            if (url === '/api/checkout') {
                logger.info('Processing checkout transaction...');
                
                // Simulate 40ms database operation
                await new Promise((r) => setTimeout(r, 40));

                res.writeHead(200, {
                    'Content-Type': 'application/json',
                    'traceparent': `00-${traceId}-${spanId}-01`
                });
                res.end(JSON.stringify({ status: 'CHECKOUT_COMPLETE', traceId }));

                const durationSec = (performance.now() - startTime) / 1000;
                httpRequestDurationHistogram.observe({ method, route: '/api/checkout', status_code: '200' }, durationSec);
                activeRequestsGauge.dec();
                logger.info({ durationSec }, 'Checkout transaction completed successfully');
                return;
            }

            res.writeHead(404);
            res.end();
            activeRequestsGauge.dec();
        });
    }

    public start(): Promise<void> {
        return new Promise((resolve) => {
            this.server.listen(this.port, '0.0.0.0', () => {
                logger.info({ port: this.port }, 'Observable HTTP Server started');
                resolve();
            });
        });
    }

    public close(): Promise<void> {
        return new Promise((resolve) => this.server.close(() => resolve()));
    }
}

async function runObservabilityLab() {
    console.log('[LAB] Starting Unified Observability & Telemetry Engine...');
    const server = new ObservableHttpServer(8085);
    await server.start();

    // 1. Simulate Client Request with Injected Traceparent
    const clientReq = http.request({
        host: '127.0.0.1',
        port: 8085,
        path: '/api/checkout',
        method: 'POST',
        headers: {
            'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
        }
    }, (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end', () => {
            console.log('[CLIENT RESPONSE]', body);
        });
    });
    clientReq.end();

    // 2. Fetch Prometheus Scrape Metrics
    setTimeout(() => {
        http.get('http://127.0.0.1:8085/metrics', (res) => {
            let metricsText = '';
            res.on('data', (c) => metricsText += c);
            res.on('end', () => {
                console.log("=================================================");
                console.log("PROMETHEUS SCRAPE METRICS SAMPLE:");
                console.log(metricsText.split('\n').filter(l => l.includes('http_request_duration') || l.includes('node_eventloop')).slice(0, 8).join('\n'));
                console.log("=================================================");
            });
        });
    }, 150);

    // Teardown
    setTimeout(async () => {
        await server.close();
        console.log('✅ Observability Lab completed successfully.');
    }, 400);
}

runObservabilityLab();
```

---

## 5. Pure Escaped CLI Snippets (Production Operations)

```bash
# 1. Compile TypeScript source code
npx tsc \
    --target ES2022 \
    --module NodeNext \
    --moduleResolution NodeNext \
    --strict \
    src/observability_engine.ts

# 2. Run with OpenTelemetry Auto-Instrumentation agent
NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register" \
node \
    --max-old-space-size=256 \
    src/observability_engine.js

# 3. Scrape and format Prometheus metrics in terminal with curl
curl -s http://localhost:8085/metrics \
    | grep -E "^(http_request_duration|node_process_cpu)"
```

---

## 6. Detailed Sub-Components & Diagnostics

### Node.js Event Loop Delay Histogram (`perf_hooks.monitorEventLoopDelay`)
* **Role & Function**: Continuously samples event loop latency at 10-millisecond intervals, exposing p50, p90, and p99 event loop lag metrics to Prometheus.
* **Inspection Command**:
  ```bash
  node -e "const { monitorEventLoopDelay } = require('node:perf_hooks'); const h = monitorEventLoopDelay(); h.enable(); setTimeout(() => { console.log('p99 lag (ns):', h.percentile(99)); }, 100);"
  ```

### W3C TraceContext Codec
* **Role & Function**: Serializes and validates 128-bit trace IDs and 64-bit span IDs across HTTP headers conforming to W3C Trace Context specifications.
* **Inspection Command**:
  ```bash
  node -e "const crypto = require('node:crypto'); console.log('W3C Header:', '00-' + crypto.randomBytes(16).toString('hex') + '-' + crypto.randomBytes(8).toString('hex') + '-01');"
  ```

---

## References

### Official Documentation
* [OpenTelemetry Node.js SDK Specification](https://opentelemetry.io/docs/languages/js/) — Distributed tracing standard.
* [Pino High-Performance Logger Reference](https://getpino.io/) — Fast JSON logging.
* [Prometheus Client for Node.js (prom-client)](https://github.com/siimon/prom-client) — Metrics collection.
* [W3C Trace Context Recommendation](https://www.w3.org/TR/trace-context/) — Distributed context header standards.
* [Node.js Async Hooks & AsyncLocalStorage](https://nodejs.org/docs/latest/api/async_context.html) — Context propagation.

### Authoritative Engineering Blogs
* [Matteo Collina: The Cost of Logging in Node.js](https://noders.com/) — Logging benchmarks and sonic-boom.
* [Brendan Gregg: Distributed Tracing & Latency Analysis](https://www.brendangregg.com/) — Observability design.
* [Netflix TechBlog: Microservice Telemetry at Scale](https://netflixtechblog.com/) — Distributed tracing.
* [Cloudflare Engineering: High-Speed Metrics Collection](https://blog.cloudflare.com/) — Metrics infrastructure.
* [Uber Engineering: Jaeger Distributed Tracing Architecture](https://www.uber.com/blog/) — OpenTelemetry origins.

---

## 7. FinOps & Cloud Resource Cost Governance

*Non-blocking logging and log-level filtering reduce observability cloud ingestion costs by 70%.*

### 1. 70% Reduction in Log Ingestion Spend (Datadog / CloudWatch)
Logging unbounded verbose debug text in high-traffic production environments generates gigabytes of unindexed data, costing $0.50/GB in AWS CloudWatch Logs or Datadog ingestion fees. Setting production log thresholds to `warn`/`error` and capturing rich structured context only on error samples saves over $3,500/month across a 100-node cluster.

### 2. Eliminating Event Loop Starvation from Logging
Switching from synchronous `console.log()` to Pino's non-blocking `sonic-boom` prevents CPU utilization spikes from log I/O, allowing containers to operate with 25% fewer CPU core reservations.

---

## 8. Troubleshooting, Diagnostic Workflows & Common Anti-Patterns

### Common Anti-Patterns

1. **Using Synchronous `console.log()` Inside Hot Request Loops**:
   - *Anti-Pattern*: Writing `console.log(JSON.stringify(req.body))` in high-QPS API handlers. `console.log()` blocks the Libuv event loop when stdout pipes fill, causing request timeouts.
   - *Fix*: Use `pino` with asynchronous destinations.

2. **Context Bleed in `AsyncLocalStorage`**:
   - *Anti-Pattern*: Mutating store objects across parallel concurrent branches within the same request.
   - *Fix*: Keep context objects strictly immutable, returning fresh cloned objects when spawning asynchronous tasks.

3. **High-Cardinality Labels in Prometheus Metrics**:
   - *Anti-Pattern*: Adding `userId` or `orderId` as label names in Prometheus histograms (`{ user_id: "12345" }`). High-cardinality labels generate millions of separate time-series in Prometheus memory, crashing the monitoring server.
   - *Fix*: Only use low-cardinality labels (e.g. `method`, `route`, `status_code`).
