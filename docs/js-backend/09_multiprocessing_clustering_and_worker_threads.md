# Module 09: Multiprocessing, Clustering & Worker Thread Pools

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Concurrency Architecture, Multiprocessing & Multi-Threading

---

## 1. Concurrency Architecture: Processes vs Threads

```text
┌─────────────────────────────────────────────────────────────┐
│                 Processes vs Worker Threads Matrix          │
├────────────────────┬────────────────────────────────────────┤
│ **`Cluster`**      │ **Independent OS Processes**           │
│ **(Processes)**    │ - Separate memory heaps (0% leakage).  │
│                    │ - Crash in 1 worker does NOT crash app!│
│                    │ - Shares HTTP Ports (80/443).          │
├────────────────────┼────────────────────────────────────────┤
│ **`Worker`**       │ **Threads in Single OS Process**       │
│ **`Threads`**      │ - Shares process memory.               │
│                    │ - Supports `SharedArrayBuffer`.        │
│                    │ - Ultra-fast O(1) zero-copy transfers. │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Zero-Downtime Rolling Reload with Cluster

When deploying updates to a production cluster, restarting all workers at once drops active user connections.

Implement **Zero-Downtime Rolling Restarts**:

```javascript
// src/cluster_master.js
import cluster from 'node:cluster';
import os from 'node:os';
import process from 'node:process';

const numCPUs = os.availableParallelism();

if (cluster.isPrimary) {
  console.log(`[Primary ${process.pid}]: Spawning ${numCPUs} clustered workers...`);

  const workers = [];
  for (let i = 0; i < numCPUs; i++) {
    workers.push(cluster.fork());
  }

  // Zero-Downtime Rolling Restart on SIGUSR2:
  process.on('SIGUSR2', async () => {
    console.log('[Primary]: Initiating Zero-Downtime Rolling Restart...');

    for (const worker of Object.values(cluster.workers)) {
      console.log(`[Rolling Restart]: Replacing worker ${worker.process.pid}...`);

      // 1. Spawn replacement worker:
      const newWorker = cluster.fork();

      // 2. Wait until new worker is online before shutting down old worker:
      await new Promise((resolve) => newWorker.once('online', resolve));

      // 3. Gracefully disconnect old worker:
      worker.disconnect();
      await new Promise((resolve) => worker.once('exit', resolve));
    }

    console.log('[Rolling Restart]: All workers replaced with zero dropped requests!');
  });
} else {
  // Worker Logic:
  import('./server.js');
}
```

---

## 3. High-Throughput Worker Thread Pool Manager

```javascript
// src/workers/thread_pool.js
import { Worker } from 'node:worker_threads';
import os from 'node:os';

export class EnterpriseThreadPool {
  constructor(workerScript, size = os.availableParallelism()) {
    this.workerScript = workerScript;
    this.size = size;
    this.workers = [];
    this.freeWorkers = [];
    this.queue = [];

    this._init();
  }

  _init() {
    for (let i = 0; i < this.size; i++) {
      const worker = new Worker(this.workerScript);
      worker.id = i;
      this.workers.push(worker);
      this.freeWorkers.push(worker);
    }
  }

  run(taskPayload) {
    return new Promise((resolve, reject) => {
      const task = { payload: taskPayload, resolve, reject };

      if (this.freeWorkers.length > 0) {
        this._dispatch(this.freeWorkers.pop(), task);
      } else {
        this.queue.push(task);
      }
    });
  }

  _dispatch(worker, task) {
    const onMessage = (result) => {
      cleanup();
      task.resolve(result);
      this._releaseWorker(worker);
    };

    const onError = (err) => {
      cleanup();
      task.reject(err);
      this._releaseWorker(worker);
    };

    const cleanup = () => {
      worker.removeListener('message', onMessage);
      worker.removeListener('error', onError);
    };

    worker.once('message', onMessage);
    worker.once('error', onError);

    worker.postMessage(task.payload);
  }

  _releaseWorker(worker) {
    if (this.queue.length > 0) {
      const nextTask = this.queue.shift();
      this._dispatch(worker, nextTask);
    } else {
      this.freeWorkers.push(worker);
    }
  }

  async destroy() {
    await Promise.all(this.workers.map((w) => w.terminate()));
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Isolate Memory Across Microservice Workers**
   Avoid relying on shared global state. Use Redis or a central database as the shared state layer rather than attempting to synchronize memory across threads.

2. **Handle Worker Uncaught Exceptions**
   If a worker thread encounters an uncaught exception, the thread terminates. Always attach `worker.on('error')` listeners to respawn crashed threads in production pools.
