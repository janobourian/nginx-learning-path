# Module 17: Performance Profiling, V8 Heap Analysis & Memory Leak Elimination

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Systems Diagnostics, V8 Profiling & Garbage Collection Analysis

---

## 1. The 3 Diagnostic Tools of Server-Side JavaScript

```text
┌─────────────────────────────────────────────────────────────┐
│                 Performance Diagnostic Suite                │
├────────────────────┬────────────────────────────────────────┤
│ **1. CPU Profiler**│ Traces function execution timestamps.  │
│                    │ Identifies un-inlined hot functions.   │
├────────────────────┼────────────────────────────────────────┤
│ **2. Heap Snapshot│ Captures V8 heap object graph.         │
│    **Analysis**    │ Identifies retained memory leaks.      │
├────────────────────┼────────────────────────────────────────┤
│ **3. GC Tracing**  │ Monitors Young & Old space collections,│
│                    │ allocation rates, and STW pause times. │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Analyzing Garbage Collection Logs (`--trace-gc`)

To inspect GC pauses and allocation rates in production:

```bash
node --trace-gc --trace-gc-verbose src/server.js
```

### Deciphering the GC Output

```text
[12345:0x104000000]   120 ms: Scavenge 18.2 (24.0) -> 6.1 (24.0) MB, 0.4 / 0.0 ms  (average mu = 0.999) allocation failure
[12345:0x104000000]   850 ms: Mark-sweep 64.5 (80.0) -> 32.1 (80.0) MB, 4.2 / 0.0 ms (average mu = 0.985) GC in old space
```

- **Scavenge (0.4ms)**: Fast Young Space collection. Normal and healthy!
- **Mark-sweep (4.2ms)**: Old Space full collection. If this exceeds 20ms or fires every 2 seconds, the application is allocating objects too quickly or suffering from a memory leak.

---

## 3. Detecting Memory Leaks with Programmatic Heap Dumps

```javascript
// src/diagnostics/memory_guard.js
import v8 from 'node:v8';
import process from 'node:process';

export function setupAutomaticMemoryGuard(maxHeapMb = 1024) {
  setInterval(() => {
    const mem = process.memoryUsage();
    const heapUsedMb = Math.round(mem.heapUsed / 1024 / 1024);

    if (heapUsedMb > maxHeapMb) {
      console.warn(`🚨 High Memory Threshold Exceeded (${heapUsedMb} MB / ${maxHeapMb} MB). Dumping Heap Snapshot...`);
      const snapshotPath = v8.writeHeapSnapshot();
      console.log(`Heap snapshot written to: ${snapshotPath}`);
    }
  }, 15000);
}
```

---

## 4. Identifying Off-Heap Memory Leaks (C++ Buffers & Descriptors)

Not all memory leaks occur inside the V8 JavaScript heap:

```text
┌─────────────────────────────────────────────────────────────┐
│                 V8 Heap vs External (Off-Heap) Memory       │
├──────────────────────────┬──────────────────────────────────┤
│ **V8 Heap Memory**       │ **External / C++ Buffer Memory** │
├──────────────────────────┼──────────────────────────────────┤
│ JavaScript Objects       │ `Buffer.alloc()` Native Memory   │
│ Closures & Maps          │ Open File Handles (`fd`)         │
│ Tracked by V8 GC         │ Native C++ Addons (OpenSSL, etc.)│
└──────────────────────────┴──────────────────────────────────┘
```

If `process.memoryUsage().rss` continues climbing while `heapUsed` stays constant, the leak is **Off-Heap**:

1. **Unclosed File Descriptors**: Check `lsof -p <PID>` on Linux/macOS.
2. **Buffer Accumulation**: Look for unclosed streams or lingering `Buffer` arrays.

---

## Troubleshooting & Best Practices

1. **Avoid Profiling in Development Mode**
   Always benchmark and profile code using production builds with optimization enabled. Development assertion checks and hot-reload watchers add 10x false overhead.

2. **Heap Snapshot Memory Spike Warning**
   Taking a V8 heap snapshot momentarily doubles the process RAM consumption while serializing the memory graph to disk. Ensure the host container has at least 2x available RAM headroom before taking production snapshots.
