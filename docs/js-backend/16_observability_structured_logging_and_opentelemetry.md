# Module 16: Enterprise Observability — Structured Logging (Pino) & OpenTelemetry (OTel)

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Observability, Distributed Tracing & Structured Logging

---

## 1. The 3 Pillars of Backend Observability

```
┌─────────────────────────────────────────────────────────────┐
│                 The 3 Observability Pillars                 │
├────────────────────┬────────────────────────────────────────┤
│ **1. Structured**  │ Machine-readable JSON logs with        │
│    **Logs**        │ Correlation IDs & request metadata.    │
│                    │ (Tool: **Pino**)                       │
├────────────────────┼────────────────────────────────────────┤
│ **2. Distributed** │ End-to-end timeline tracing across     │
│    **Traces**      │ microservices and databases.           │
│                    │ (Tool: **OpenTelemetry / OTel**)       │
├────────────────────┼────────────────────────────────────────┤
│ **3. System**      │ Numerical aggregations & counters.     │
│    **Metrics**     │ (Tool: **Prometheus / OpenMetrics**)   │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Context Propagation with `AsyncLocalStorage` (`node:async_hooks`)

In asynchronous Node.js code, passing a `requestId` down through 20 database queries and service functions (parameter drilling) is error-prone.

**`AsyncLocalStorage`** provides thread-local-like context storage that persists across all asynchronous callbacks and awaits automatically:

```javascript
// src/observability/request_context.js
import { AsyncLocalStorage } from 'node:async_hooks';

export const requestContextStorage = new AsyncLocalStorage();

export function getCorrelationId() {
  const store = requestContextStorage.getStore();
  return store?.correlationId || 'system-background';
}
```

```javascript
// src/middleware/correlation_middleware.js
import crypto from 'node:crypto';
import { requestContextStorage } from '../observability/request_context.js';

export function correlationMiddleware(req, res, next) {
  // Read incoming W3C traceparent or generate new UUID:
  const correlationId = req.headers['x-correlation-id'] || crypto.randomUUID();
  res.setHeader('x-correlation-id', correlationId);

  // Run all downstream handlers inside the context store:
  requestContextStorage.run({ correlationId, userId: null }, () => {
    next();
  });
}
```

---

## 3. High-Performance JSON Logging with Pino

**Pino** is the fastest JSON logger in the Node.js ecosystem, formatting logs asynchronously without blocking the event loop:

```bash
npm install pino pino-http
```

```javascript
// src/observability/logger.js
import pino from 'pino';
import { getCorrelationId } from './request_context.js';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  // Automatically inject correlationId into every log line:
  mixin() {
    return { correlationId: getCorrelationId() };
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});
```

---

## 4. Distributed Tracing with OpenTelemetry (OTel)

```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-http
```

### Initializing the OpenTelemetry SDK (`src/instrumentation.js`):

```javascript
// src/instrumentation.js
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';

// Configure OTLP Exporter pointing to Jaeger / Datadog / Grafana Tempo:
const traceExporter = new OTLPTraceExporter({
  url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces',
});

export const otelSdk = new NodeSDK({
  traceExporter,
  instrumentations: [
    getNodeAutoInstrumentations({
      // Auto-instruments HTTP, Express, Fastify, pg, redis, and fetch!
      '@opentelemetry/instrumentation-fs': { enabled: false }, // Reduce noise
    }),
  ],
});

otelSdk.start();
console.log('🔭 OpenTelemetry SDK initialized successfully.');

process.on('SIGTERM', () => {
  otelSdk.shutdown().then(() => console.log('OTel SDK shut down cleanly.'));
});
```

```bash
# Preload instrumentation before application code boots:
node --import ./src/instrumentation.js src/server.js
```

---

## 5. Custom OpenTelemetry Spans

```javascript
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('enterprise-order-service');

export async function processPaymentWithSpan(orderId, amount) {
  // Create a custom trace span:
  return await tracer.startActiveSpan('processPayment', async (span) => {
    span.setAttribute('order.id', orderId);
    span.setAttribute('order.amount', amount);

    try {
      const result = await executeStripePayment(amount);
      span.setStatus({ code: 1 }); // OK
      return result;
    } catch (err) {
      span.recordException(err);
      span.setStatus({ code: 2, message: err.message }); // ERROR
      throw err;
    } finally {
      span.end(); // ◄── Close span
    }
  });
}
```

---

## Troubleshooting & Best Practices

1. **Never Log Sensitive PII (Personally Identifiable Information)**
   Configure Pino redactors to automatically scrub sensitive fields:
   ```javascript
   const logger = pino({
     redact: ['req.headers.authorization', 'password', 'creditCard.number'],
   });
   ```

2. **Propagate W3C `traceparent` Headers**
   When making outgoing HTTP requests to other internal microservices, ensure OpenTelemetry forwards the `traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01` header to maintain continuous end-to-end distributed traces.
