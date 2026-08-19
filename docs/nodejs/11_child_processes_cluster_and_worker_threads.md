# Module 11: Child Processes, Cluster & Worker Threads Multi-Threading

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Concurrency, Multi-Processing & Worker Threads

---

## 1. The 3 Node.js Concurrency Paradigms

Because a single Node.js instance runs user code on one V8 thread, scaling across a 64-core CPU server requires choosing the right concurrency model:

| Concurrency Mechanism | Architecture | Memory Isolation | Port Sharing | Best Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **`node:child_process`** | Spawns separate OS processes | **100% Isolated** | No | Executing system binaries (`ffmpeg`, `git`, `python`, `bash`) |
| **`node:cluster`** | Master / Worker processes | **100% Isolated** | **Yes (Shares Port 80/443)** | Scaling HTTP/WebSocket server throughput across all CPU cores |
| **`node:worker_threads`** | True OS threads in single process | **Shared Memory Available (`SharedArrayBuffer`)** | No | CPU-intensive JavaScript tasks (image processing, PDF generation, cryptography) |

---

## 2. Multi-Core Scaling with `node:cluster`

The **`cluster`** module forks multiple copies of your Node.js application, allowing all workers to listen on the exact same HTTP port:

```javascript
// src/cluster_server.js
import cluster from 'node:cluster';
import http from 'node:http';
import os from 'node:os';
import process from 'node:process';

const numCPUs = os.availableParallelism();

if (cluster.isPrimary) {
  console.log(`[Primary Master ${process.pid}]: Forking ${numCPUs} worker processes across CPU cores...`);

  // Fork workers for each CPU core:
  for (let i = 0; i < numCPUs; i++) {
    cluster.fork();
  }

  // Automatic Worker Resurrection on Crash:
  cluster.on('exit', (worker, code, signal) => {
    console.warn(`[Worker ${worker.process.pid}] died (code: ${code}, signal: ${signal}). Spawning replacement...`);
    cluster.fork();
  });
} else {
  // Worker Process:
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'OK',
      workerPid: process.pid,
      time: new Date().toISOString(),
    }));
  });

  server.listen(8080, () => {
    console.log(`[Worker ${process.pid}]: Listening on port 8080`);
  });
}
```

---

## 3. High-Performance Multi-Threading with `node:worker_threads`

Unlike `child_process` (which incurs ~30MB memory per process and OS context switches), **Worker Threads** run in the same OS process and can transfer data in **0ms via `transferList` and `SharedArrayBuffer`**:

### 1. The Worker Script (`src/workers/heavy_compute.worker.js`)

```javascript
// src/workers/heavy_compute.worker.js
import { parentPort } from 'node:worker_threads';

// Listen for CPU-bound computation tasks from main thread:
parentPort.on('message', ({ taskId, dataArray }) => {
  // Heavy CPU computation (e.g. prime factor calculation or hashing):
  let result = 0;
  for (let i = 0; i < dataArray.length; i++) {
    result = (result + dataArray[i] * 31) ^ (i & 0xFF);
  }

  // Send result back to main thread:
  parentPort.postMessage({ taskId, result });
});
```

---

### 2. The Main Thread Worker Controller

```javascript
// src/main_worker_pool.js
import { Worker } from 'node:worker_threads';
import path from 'node:path';

class WorkerTaskDispatcher {
  constructor(workerScript) {
    this.worker = new Worker(workerScript);
    this.pendingTasks = new Map();

    this.worker.on('message', ({ taskId, result }) => {
      const resolver = this.pendingTasks.get(taskId);
      if (resolver) {
        resolver(result);
        this.pendingTasks.delete(taskId);
      }
    });

    this.worker.on('error', (err) => {
      console.error('[Worker Thread Error]:', err);
    });
  }

  executeTask(dataArray) {
    const taskId = `task_${Date.now()}_${Math.random()}`;
    return new Promise((resolve) => {
      this.pendingTasks.set(taskId, resolve);
      this.worker.postMessage({ taskId, dataArray });
    });
  }

  terminate() {
    return this.worker.terminate();
  }
}

// Execution:
async function run() {
  const dispatcher = new WorkerTaskDispatcher(
    path.resolve('src/workers/heavy_compute.worker.js')
  );

  const sampleData = Array.from({ length: 1000000 }, (_, i) => i);

  console.log('Dispatching CPU-intensive job to Worker Thread...');
  const result = await dispatcher.executeTask(sampleData);
  console.log('Worker Thread finished computation! Result:', result);

  await dispatcher.terminate();
}

run();
```

---

## 4. Zero-Copy Shared Memory with `SharedArrayBuffer` & `Atomics`

To share memory between threads with **zero serialization overhead**, use **`SharedArrayBuffer`** with thread-safe **`Atomics`**:

```javascript
// Allocate 1MB of shared memory across threads:
const sharedBuffer = new SharedArrayBuffer(1024 * 1024);
const sharedInt32Array = new Int32Array(sharedBuffer);

// Thread-safe atomic increment without race conditions:
Atomics.add(sharedInt32Array, 0, 1);

// Thread synchronization (Wait / Notify):
// Worker 1: Atomics.wait(sharedInt32Array, 0, 0); // Sleeps until value changes!
// Worker 2: Atomics.notify(sharedInt32Array, 0, 1); // Wakes up 1 sleeping thread!
```

---

## Troubleshooting & Best Practices

1. **Never Spawn Worker Threads Per HTTP Request**
   Creating a `new Worker()` incurs ~10ms V8 isolate instantiation overhead. Always use a pre-warmed **Worker Thread Pool** (e.g. `piscina`) with a pool size equal to `os.availableParallelism()`.

2. **Cluster vs Worker Threads Decision**

   - Use **`cluster`** for I/O-bound web microservices to maximize HTTP connection concurrency across CPU cores.
   - Use **`worker_threads`** for CPU-bound computations (JSON parsing of 500MB payloads, image resizing, machine learning tokenization).
