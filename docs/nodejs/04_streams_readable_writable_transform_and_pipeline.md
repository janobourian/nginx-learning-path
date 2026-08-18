# Module 04: Node.js Streams, Backpressure & `stream.pipeline`

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Stream Processing, Backpressure & Pipeline Architecture

---

## 1. Why Streams Are Essential for Enterprise Node.js

Consider an HTTP server that reads a 5GB file and sends it to a client:

```javascript
// ❌ HORRIBLE: Loads 5GB into V8 Heap Memory! Crashes with Out-Of-Memory (OOM)!
const fileBuffer = fs.readFileSync('huge-dataset.csv');
res.end(fileBuffer);
```

With **Streams**, data is read and transmitted chunk-by-chunk (typically 64KB chunks). A 50GB file can be streamed to 1,000 clients simultaneously with **constant, bounded memory (< 30MB RAM total)**!

```
Stream Pipeline:
[Source: 50GB File] ──► [ReadableStream] ──(64KB Chunks)──► [TransformStream (Gzip)] ──► [WritableStream (HTTP Response)]
Memory Footprint: Bounded to ~64KB at any given microsecond!
```

---

## 2. The 4 Fundamental Stream Types

```
┌─────────────────────────────────────────────────────────────┐
│                    The 4 Node.js Stream Types               │
├───────────────────┬─────────────────────────────────────────┤
│ **`Readable`**    │ Data source you pull chunks from        │
│                   │ (e.g. `fs.createReadStream`, `req`).    │
├───────────────────┼─────────────────────────────────────────┤
│ **`Writable`**    │ Data sink you push chunks to            │
│                   │ (e.g. `fs.createWriteStream`, `res`).   │
├───────────────────┼─────────────────────────────────────────┤
│ **`Duplex`**      │ Both Readable and Writable              │
│                   │ (e.g. `net.Socket`, TCP connections).   │
├───────────────────┼─────────────────────────────────────────┤
│ **`Transform`**   │ A Duplex stream that modifies chunks    │
│                   │ on-the-fly (e.g. `zlib.createGzip`).    │
└───────────────────┴─────────────────────────────────────────┘
```

---

## 3. Backpressure & The `drain` Event

**Backpressure** occurs when a `Readable` stream produces data faster than the destination `Writable` stream can write it (e.g. reading from a fast NVMe SSD at 2GB/sec and writing to a slow 3G mobile network socket at 100KB/sec).

Without backpressure, unwritten chunks accumulate in RAM, triggering OOM crashes.

### The Backpressure Handshake:
1. `writable.write(chunk)` returns `false` when internal buffer exceeds **`highWaterMark`** (default: 16KB for objects, 64KB for byte streams).
2. The producer pauses reading (`readable.pause()`).
3. When the consumer's buffer empties, the writable emits the **`drain`** event.
4. The producer resumes reading (`readable.resume()`).

```javascript
// Manual Backpressure Implementation:
function writeWithBackpressure(readable, writable) {
  readable.on('data', (chunk) => {
    const canContinue = writable.write(chunk);
    if (!canContinue) {
      // Pause incoming stream:
      readable.pause();
      // Resume when buffer drains:
      writable.once('drain', () => {
        readable.resume();
      });
    }
  });
}
```

---

## 4. Why `readable.pipe()` Is Dangerous (And Why `pipeline` Replaces It)

Legacy code used `readable.pipe(transform).pipe(writable)`.

### Why `.pipe()` Is Forbidden in Production:
- If an error occurs in the middle of a `.pipe()` chain, **`.pipe()` does NOT close or destroy the other streams in the pipeline**.
- This causes lingering open file handles, socket descriptor leaks, and memory leaks.

### The Modern Standard: `stream.pipeline` with `async/await`

**`stream/promises.pipeline`** forwards all data, handles backpressure automatically, and **guarantees that all streams are safely destroyed and closed on both success and error**:

```javascript
import { pipeline } from 'node:stream/promises';
import fs from 'node:fs';
import zlib from 'node:zlib';

async function compressLogArchive(inputPath, outputPath) {
  try {
    await pipeline(
      fs.createReadStream(inputPath),      // 1. Read source
      zlib.createGzip({ level: 9 }),       // 2. Compress with Gzip
      fs.createWriteStream(outputPath)     // 3. Write destination
    );
    console.log('Log compression completed with zero memory leaks!');
  } catch (error) {
    console.error('Pipeline failed. All stream file handles closed safely:', error);
  }
}
```

---

## 5. Custom `Transform` Stream (Streaming Line-by-Line CSV Parser)

```javascript
// src/streams/csv_transformer.js
import { Transform } from 'node:stream';

export class CsvToJsonTransform extends Transform {
  constructor(options) {
    super({ ...options, objectMode: true });
    this._buffer = '';
    this._headers = null;
  }

  _transform(chunk, encoding, callback) {
    this._buffer += chunk.toString('utf8');
    const lines = this._buffer.split('\n');

    // Keep the trailing incomplete line chunk in the buffer:
    this._buffer = lines.pop() || '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      const columns = trimmed.split(',');

      if (!this._headers) {
        this._headers = columns; // First line = Headers
      } else {
        const record = {};
        for (let i = 0; i < this._headers.length; i++) {
          record[this._headers[i]] = columns[i];
        }
        // Push parsed JSON object to downstream consumers:
        this.push(record);
      }
    }

    callback(); // Signal ready for next chunk
  }

  _flush(callback) {
    // Process any remaining bytes on stream end:
    if (this._buffer.trim() && this._headers) {
      const columns = this._buffer.trim().split(',');
      const record = {};
      for (let i = 0; i < this._headers.length; i++) {
        record[this._headers[i]] = columns[i];
      }
      this.push(record);
    }
    callback();
  }
}
```

---

## 6. Consuming Streams with `for await...of` (Async Iterables)

Every Node.js `Readable` stream is an **Async Iterable**:

```javascript
import fs from 'node:fs';

async function processStreamAsync(filePath) {
  const readStream = fs.createReadStream(filePath, { encoding: 'utf8' });

  for await (const chunk of readStream) {
    console.log(`Received chunk (${chunk.length} characters)`);
  }
  console.log('Stream finished.');
}
```

---

## Troubleshooting & Best Practices

1. **Always Use `stream/promises.pipeline`**
   Never use `.pipe()` in production. Always use `await pipeline(...)` wrapped in a `try/catch` block.

2. **Handle Web Stream vs Node Stream Interoperability**
   In Node.js 20+, convert between Web Streams (`ReadableStream`) and Node.js Streams (`Readable`) using:
   - `Readable.fromWeb(webStream)`
   - `Readable.toWeb(nodeStream)`
