# Module 02: Backend Streams, WHATWG Web Streams & Backpressure Pipelines

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Stream Processing, WHATWG Standards & Backpressure Mechanics

---

## 1. Node.js Streams vs WHATWG Web Streams

Modern backend architectures use two stream standards:
1. **Node.js Streams (`node:stream`)**: Built on `EventEmitter` (`Readable`, `Writable`, `Transform`, `pipeline`).
2. **WHATWG Web Streams Standard**: The unified browser/edge/runtime standard (`ReadableStream`, `WritableStream`, `TransformStream`) native to Deno, Bun, Cloudflare Workers, and Node.js 18+.

```
┌─────────────────────────────────────────────────────────────┐
│                 Stream Standard API Mapping                 │
├──────────────────────────┬──────────────────────────────────┤
│ Node.js Stream API       │ WHATWG Web Stream Standard       │
├──────────────────────────┼──────────────────────────────────┤
│ `Readable`               │ `ReadableStream`                 │
│ `Writable`               │ `WritableStream`                 │
│ `Transform`              │ `TransformStream`                │
│ `stream.pipeline()`      │ `readable.pipeThrough().pipeTo()`│
└──────────────────────────┴──────────────────────────────────┘
```

---

## 2. Transforming Web Streams (`TransformStream`)

A **`TransformStream`** accepts chunks from a readable source, processes or compresses them, and passes transformed chunks to downstream consumers:

```javascript
// src/streams/ndjson_transformer.js

export function createNdjsonParseStream() {
  let buffer = '';

  return new TransformStream({
    transform(chunk, controller) {
      buffer += typeof chunk === 'string' ? chunk : new TextDecoder().decode(chunk);
      const lines = buffer.split('\n');

      // Keep trailing incomplete chunk in buffer:
      buffer = lines.pop() || '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed) {
          try {
            const parsedObject = JSON.parse(trimmed);
            // Enqueue parsed JSON object downstream:
            controller.enqueue(parsedObject);
          } catch (err) {
            controller.error(new Error(`Corrupted NDJSON line: ${err.message}`));
          }
        }
      }
    },
    flush(controller) {
      if (buffer.trim()) {
        try {
          controller.enqueue(JSON.parse(buffer.trim()));
        } catch (err) {
          controller.error(err);
        }
      }
    },
  });
}
```

---

## 3. High-Performance Web Stream Pipeline with Backpressure

Let's build a cross-runtime stream pipeline that reads a multi-gigabyte log file stream, parses NDJSON records, filters for critical errors, encodes back to bytes, and compresses via Gzip **with constant <20MB memory**:

```javascript
// src/pipelines/log_analysis_pipeline.js
import { CompressionStream } from 'node:stream/web';

export async function processLogStream(readableByteStream, destinationWritableStream) {
  const filterCriticalLogs = new TransformStream({
    transform(logEntry, controller) {
      // Filter records:
      if (logEntry.level === 'CRITICAL' || logEntry.statusCode >= 500) {
        const enriched = JSON.stringify({
          ...logEntry,
          processedAt: new Date().toISOString(),
        }) + '\n';
        controller.enqueue(new TextEncoder().encode(enriched));
      }
    },
  });

  // Compose streaming pipeline with automatic backpressure:
  await readableByteStream
    .pipeThrough(createNdjsonParseStream())      // 1. Parse NDJSON
    .pipeThrough(filterCriticalLogs)              // 2. Filter & Enrich
    .pipeThrough(new CompressionStream('gzip'))   // 3. Compress with Gzip
    .pipeTo(destinationWritableStream);           // 4. Write to destination

  console.log('Stream pipeline completed with zero memory accumulation.');
}
```

---

## 4. Converting Between Node Streams and Web Streams

```javascript
import { Readable, Writable } from 'node:stream';

// Convert WebStream -> Node.js Stream:
const nodeReadable = Readable.fromWeb(webReadableStream);

// Convert Node.js Stream -> WebStream:
const webStream = Readable.toWeb(nodeReadable);
```

---

## Troubleshooting & Best Practices

1. **Always Handle Web Stream Cancellation**
   When consuming a `ReadableStream` manually via `reader.read()`, if an error occurs or processing terminates early, always call `reader.cancel()` to close upstream network sockets and release file descriptors.

2. **Beware of Object Mode HighWaterMark**
   In Node streams, `highWaterMark: 16` for object streams means **16 objects**, not 16KB. For massive objects (e.g. 1MB JSON trees), set `highWaterMark: 2` to prevent memory spikes.
