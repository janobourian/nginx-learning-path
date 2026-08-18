# Module 17: Performance Diagnostics, Memory Leaks & V8 Profiling

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Diagnostics, Memory Leaks & CPU Flamegraphs

---

## 1. The 3 Diagnostic Tools of Node.js

When an enterprise Node.js microservice suffers from 100% CPU spikes or steadily climbs in RAM until an Out-Of-Memory (OOM) crash, use these three diagnostic layers:

```
┌─────────────────────────────────────────────────────────────┐
│                 Node.js Diagnostics Toolset                 │
├────────────────────┬────────────────────────────────────────┤
│ **1. CPU Profiler**│ **Identifies Hot Code & Bottlenecks**  │
│                    │ - Traces V8 JIT execution samples.     │
│                    │ - Generates Flamegraphs (`0x`).        │
├────────────────────┼────────────────────────────────────────┤
│ **2. Heap Snapshot│ **Finds Memory Leaks & Retained Objects│
│    **Inspector**   │ - Captures V8 heap graph at runtime.   │
│                    │ - Analyzes retainer trees in DevTools. │
├────────────────────┼────────────────────────────────────────┤
│ **3. Diagnostic**  │ **Post-Mortem Crash Analysis**         │
│    **Reports**     │ - Dumps OS thread state & libuv handles│
│                    │   on unhandled exceptions/fatal OOM.   │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Generating & Analyzing CPU Profiles (`node --prof`)

### Step 1: Collect Profiling Samples Under Load
```bash
# Start server with V8 tick profiler enabled:
node --prof src/server.js
```

### Step 2: Generate Traffic (e.g. via `autocannon`):
```bash
autocannon -c 50 -d 10 http://localhost:3000/api/heavy-work
```

### Step 3: Process the Binary Tick Log:
```bash
# Process isolate log into human-readable text:
node --prof-process isolate-0x*.log > v8_profile.txt
```

In `v8_profile.txt`, inspect the **`[Bottom up (heavy) profile]`** section to identify the exact functions consuming the highest percentage of CPU ticks.

---

## 3. Visual Flamegraphs with `0x`

A **Flamegraph** visualizes the entire call stack over time. The width of each bar corresponds directly to the total CPU time spent in that function:

```bash
# Run server with 0x flamegraph profiler:
npx 0x src/server.js
```
After stopping the process, `0x` automatically generates an interactive HTML flamegraph in your browser.

---

## 4. Diagnosing Memory Leaks with Heap Snapshots (`node:v8`)

A **Memory Leak** occurs when objects in the V8 heap are no longer needed by application logic, but remain referenced by a root variable (preventing the Garbage Collector from collecting them).

### Taking Heap Snapshots Programmatically on Demand:

```javascript
// src/diagnostics/heap_dumper.js
import v8 from 'node:v8';
import path from 'node:path';

export function captureHeapSnapshot() {
  const fileName = `heap-${Date.now()}-${process.pid}.heapsnapshot`;
  const filePath = path.resolve('diagnostics', fileName);

  console.log(`[Heap Dumper]: Writing V8 heap snapshot to ${filePath}...`);
  const writtenPath = v8.writeHeapSnapshot(filePath);
  console.log(`[Heap Dumper]: Snapshot saved: ${writtenPath}`);
  return writtenPath;
}
```

### Analyzing Heap Snapshots in Chrome DevTools:
1. Open Google Chrome and navigate to `chrome://inspect`.
2. Click **Open dedicated DevTools for Node**.
3. Go to the **Memory Tab** and click **Load**.
4. Import **Snapshot A** (Baseline) and **Snapshot B** (After 1,000 requests).
5. Switch the view from *Summary* to **Comparison** to see objects whose count increased without being garbage-collected!

---

## 5. The 3 Most Common Node.js Memory Leaks (And Solutions)

### Leak 1: Unbounded In-Memory Caches

```javascript
// ❌ MEMORY LEAK: Map grows indefinitely with every incoming request:
const userCache = new Map();

function cacheUser(userId, userData) {
  userCache.set(userId, userData); // Never evicts old keys!
}

// ✅ FIX: Use an LRU (Least Recently Used) cache with strict size limits:
import { LRUCache } from 'lru-cache';

const safeUserCache = new LRUCache({
  max: 5000,              // Keep at most 5,000 items
  ttl: 1000 * 60 * 5,     // 5-minute TTL
});
```

---

### Leak 2: Lingering `EventEmitter` Listeners

If you register `.on('event')` listeners on long-lived singletons without removing them on request completion:

```javascript
// ❌ LEAK: Adds a new listener on globalBus on EVERY HTTP request!
app.get('/data', (req, res) => {
  globalBus.on('data_ready', () => res.send('ok')); // Listener retained in memory!
});

// ✅ FIX: Use .once() or remove listener explicitly:
app.get('/data', (req, res) => {
  globalBus.once('data_ready', () => res.send('ok'));
});
```

---

### Leak 3: Closures Retaining Large Outer Scope Buffers

```javascript
// ❌ LEAK: Inner callback retains the entire 50MB buffer in memory:
function processFile() {
  const hugeBuffer = Buffer.alloc(50 * 1024 * 1024); // 50MB
  const recordId = '101';

  return function getRecordId() {
    // Even though only recordId is accessed, V8 may retain hugeBuffer in the lexical scope context!
    return recordId;
  };
}
```

---

## 6. Node.js Diagnostic Crash Reports (`node:process`)

Generate a complete JSON diagnostic report detailing native OS threads, environment variables, libuv handles, and resource limits:

```javascript
import process from 'node:process';

// Automatically write report on unhandled exceptions:
process.report.reportOnUncaughtException = true;
process.report.reportOnSignal = true; // Write report on SIGUSR2
process.report.directory = './diagnostics';
```

---

## Troubleshooting & Best Practices

1. **Watch Out for `MaxListenersExceededWarning`**
   If Node outputs `Possible EventEmitter memory leak detected. 11 event listeners added`, inspect your code immediately. Do not simply silence the warning with `setMaxListeners(0)`.

2. **Never Profile in Development / JIT Warm-Up**
   Always warm up the server by sending 1,000 initial requests before taking baseline heap snapshots or CPU profile traces.
