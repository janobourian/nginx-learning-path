# Module 08: Web Workers, SharedWorkers, `SharedArrayBuffer` & Multi-Threading

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** Browser Concurrency, Multi-Threading & Shared Memory

---

## 1. Multi-Threading in Modern Web Browsers

JavaScript execution on the main browser thread is single-threaded. Running CPU-heavy algorithms (e.g. image filters, PDF rendering, cryptography, 100MB CSV parsing) blocks the UI thread, freezing animations, touch responses, and dropping frame rates to 0fps.

**Web Workers** allow you to execute JavaScript in true background OS threads without blocking the main UI thread:

```
┌─────────────────────────────────────────────────────────────┐
│                 The 3 Web Worker Paradigms                  │
├────────────────────┬────────────────────────────────────────┤
│ **1. Dedicated**   │ Single thread owned by one page tab.   │
│    **Worker**      │ Ideal for image processing & parsing.  │
├────────────────────┼────────────────────────────────────────┤
│ **2. SharedWorker**│ Single thread **shared across ALL open │
│                    │ tabs / windows** on the same origin.   │
│                    │ Ideal for global WebSocket connections.│
├────────────────────┼────────────────────────────────────────┤
│ **3. Service**     │ Event-driven background network proxy  │
│    **Worker**      │ and offline cache controller.          │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Dedicated Web Workers with ESM Modules

Modern browsers support ES Module imports inside Web Workers (`{ type: 'module' }`):

### 1. The Worker Script (`src/workers/image_processor.worker.js`)

```javascript
// src/workers/image_processor.worker.js

self.addEventListener('message', (event) => {
  const { taskId, imageData, filterType } = event.data;
  const pixels = imageData.data;

  // Apply Grayscale filter to millions of pixels in background thread:
  if (filterType === 'grayscale') {
    for (let i = 0; i < pixels.length; i += 4) {
      const avg = (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3;
      pixels[i] = avg;     // R
      pixels[i + 1] = avg; // G
      pixels[i + 2] = avg; // B
    }
  }

  // 2. Transfer binary buffer back to main thread in ZERO-COPY O(1) time:
  self.postMessage(
    { taskId, imageData },
    [imageData.data.buffer] // ◄── Transferable Object List (Zero-Copy!)
  );
});
```

---

### 2. Main Thread Controller

```javascript
// src/main.js
const worker = new Worker(
  new URL('./workers/image_processor.worker.js', import.meta.url),
  { type: 'module' }
);

export function processImageInBackground(imageData, filterType = 'grayscale') {
  return new Promise((resolve) => {
    const taskId = `task_${Date.now()}`;

    const handler = (event) => {
      if (event.data.taskId === taskId) {
        worker.removeEventListener('message', handler);
        resolve(event.data.imageData);
      }
    };

    worker.addEventListener('message', handler);

    // Transfer buffer to worker (Zero-copy ownership transfer!):
    worker.postMessage(
      { taskId, imageData, filterType },
      [imageData.data.buffer] // ◄── Ownership transferred to worker!
    );
  });
}
```

---

## 3. Cross-Tab Shared State with `SharedWorker`

A **`SharedWorker`** allows 10 open browser tabs to share a single background thread and a single WebSocket connection:

```javascript
// src/workers/shared_connection.worker.js
const ports = new Set();

self.addEventListener('connect', (event) => {
  const port = event.ports[0];
  ports.add(port);

  port.addEventListener('message', (e) => {
    // Broadcast message to ALL open browser tabs:
    for (const p of ports) {
      p.postMessage(`[Broadcast from Tab]: ${e.data}`);
    }
  });

  port.start(); // Required when using addEventListener!
});
```

```javascript
// In every browser tab:
const sharedWorker = new SharedWorker(
  new URL('./workers/shared_connection.worker.js', import.meta.url),
  { type: 'module' }
);

sharedWorker.port.addEventListener('message', (e) => {
  console.log('Received across tabs:', e.data);
});
sharedWorker.port.start();

sharedWorker.port.postMessage('Tab connected!');
```

---

## 4. Shared Memory & Atomics (`SharedArrayBuffer`)

For high-performance 3D rendering and audio processing, copying buffers via `postMessage` adds overhead.

Using **`SharedArrayBuffer`**, multiple threads read and mutate the **exact same memory address simultaneously**:

```javascript
// Allocate 64KB shared memory:
const sharedBuffer = new SharedArrayBuffer(65536);
const sharedInt32 = new Int32Array(sharedBuffer);

// Thread 1: Wait until index 0 becomes non-zero:
// Atomics.wait(sharedInt32, 0, 0); // (Only allowed in Workers, NOT main thread!)

// Thread 2: Atomic update & wake up sleeping thread:
Atomics.store(sharedInt32, 0, 42);
Atomics.notify(sharedInt32, 0, 1); // Wakes up 1 waiting worker!
```

---

## 5. Security Requirements for `SharedArrayBuffer` (COOP / COEP)

To protect against **Spectre CPU side-channel attacks**, browsers disable `SharedArrayBuffer` unless the web server sends **Cross-Origin Isolation Headers**:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

---

## Troubleshooting & Best Practices

1. **DOM Access Is Forbidden in Web Workers**
   Web Workers have no access to `window`, `document`, or DOM elements. They communicate strictly through message passing (`postMessage`), WebSockets, or IndexedDB.

2. **Always Use Transferable Objects for Large Buffers**
   When passing `ArrayBuffer`, `ImageBitmap`, or `OffscreenCanvas` to a worker, always pass the buffer in the second `transfer` array (`postMessage(data, [data.buffer])`) to transfer memory ownership in 0ms without copying bytes.
