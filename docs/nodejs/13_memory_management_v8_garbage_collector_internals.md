# Module 13: V8 Garbage Collector Internals, Scavengers & Mark-Sweep

**Track:** Node.js Enterprise Backend & Runtime
**Directory:** `docs/nodejs/`
**File:** `13_memory_management_v8_garbage_collector_internals.md`
**Category:** Memory Architecture, Garbage Collection & V8 Internals
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. High-Level Overview & Architectural Foundations

Memory management in Node.js is executed automatically by the **Google V8 Generational Garbage Collector**. In high-concurrency microservices processing tens of thousands of requests per second, understanding how V8 allocates, promotes, marks, sweeps, and compacts memory is essential to prevent stop-the-world latency spikes.

V8's memory management is founded upon the **Weak Generational Hypothesis**: *most objects die young*. To optimize CPU cycles, V8 divides heap memory into two distinct generations:

1. **Young Generation (New Space)**: Manages short-lived allocations (request parameters, temporary strings, loop closures) using a fast **Semi-Space Scavenger GC (Cheney's Copying Algorithm)**.
2. **Old Generation (Old Space)**: Holds objects that survived multiple Scavenger cycles, managed by a comprehensive **Mark-Sweep-Compact Major GC** utilizing incremental marking, concurrent sweeping, and memory page compaction.

```text
+-------------------------------------------------------------------------------+
|                       Google V8 Heap Generation Layout                        |
+-------------------------------------------------------------------------------+

  [ YOUNG GENERATION / NEW SPACE ]                [ OLD GENERATION / OLD SPACE ]
  +-------------------------------+              +-------------------------------+
  |  From-Space   |   To-Space    |              |  Old Pointer Space            |
  |  (Active Allocations: 16MB)   |  Promote     |  (Objects with pointers)      |
  |               |               |  =========>  +-------------------------------+
  |  Cheney's Copying Scavenger   |  (Survives   |  Old Data Space               |
  |  (Fast Pointer-Bump Alloc)    |   2 cycles)  |  (Raw strings, boxed numbers) |
  +-------------------------------+              +-------------------------------+
                                                 |  Large Object Space (> 512KB) |
                                                 +-------------------------------+
                                                 |  Code Space (JIT Instructions)|
                                                 +-------------------------------+
```

---

## 2. Complete V8 Memory & Garbage Collection API Dictionary

Below is the complete API dictionary for V8 memory inspection and garbage collection control in Node.js:

| Class / Method / Flag | Module / CLI | Signature | Operational Execution Semantics |
| :--- | :--- | :--- | :--- |
| `v8.getHeapStatistics()` | `node:v8` | `v8.getHeapStatistics(): HeapInfo` | Returns total heap size, executable size, total physical size, and heap limits in bytes. |
| `v8.getHeapSpaceStatistics()` | `node:v8` | `v8.getHeapSpaceStatistics(): HeapSpaceInfo[]` | Returns per-space breakdown (new_space, old_space, code_space, map_space, large_object_space). |
| `v8.setFlagsFromString(flags)` | `node:v8` | `v8.setFlagsFromString(flags: string): void` | Dynamically updates V8 virtual machine flags at runtime (e.g. `--trace-gc`). |
| `global.gc()` | Global | `global.gc(): void` | Manually triggers a synchronous Mark-Sweep-Compact Major GC (requires `--expose-gc` flag). |
| `process.memoryUsage()` | `process` | `process.memoryUsage(): MemoryUsage` | Returns `{ rss, heapTotal, heapUsed, external, arrayBuffers }`. |
| `--max-old-space-size=N` | CLI Flag | `node --max-old-space-size=512 app.js` | Sets the maximum Old Generation heap ceiling in megabytes. |
| `--trace-gc` | CLI Flag | `node --trace-gc app.js` | Emits single-line stdout logs for every Scavenger and Mark-Sweep GC cycle. |
| `--trace-gc-verbose` | CLI Flag | `node --trace-gc-verbose app.js` | Emits detailed per-space memory breakdown and heap state before/after GC. |
| `--trace-gc-nvp` | CLI Flag | `node --trace-gc-nvp app.js` | Outputs GC diagnostics in structured Name-Value Pair format for automated parsing. |

---

## 3. Technical Deep Dive: Scavenger vs Mark-Sweep-Compact Mechanics

### A. The Scavenger GC (Minor GC — Cheney's Copying Algorithm)

* **Allocation**: Fast pointer-bumping in `From-Space`.
* **Execution**: When `From-Space` fills, V8 halts JavaScript execution briefly ($< 0.5\text{ms}$).
* **Copying**: It traverses live objects reachable from the root set, copying live objects contiguously into `To-Space`.
* **Pointer Flip**: The roles of `From-Space` and `To-Space` are swapped. Dead objects left behind in the old space are instantly reclaimed.
* **Promotion**: Any object that survives two consecutive Scavenger passes is promoted to Old Space.

### B. Mark-Sweep-Compact (Major GC — Tri-Color Marking Algorithm)

* **Marking Phase (Tri-Color)**:
  * **White**: Unvisited objects (candidates for collection).
  * **Grey**: Visited objects whose children have not yet been evaluated.
  * **Black**: Visited objects with all referenced children fully evaluated.
* **Incremental Marking**: V8 splits the marking phase into tiny 5-microsecond slices interleaved between normal JavaScript execution turns, eliminating multi-second stop-the-world freezes.
* **Concurrent Sweeping**: Dedicated background C++ threads sweep through Old Space pages to reclaim dead white objects without pausing the main thread.
* **Compaction**: Moves fragmented black objects to contiguous memory pages to eliminate heap fragmentation.

---

## 4. Hands-On Step-by-Step Production Lab: Real-Time GC Telemetry Engine

This production lab creates a non-invasive Garbage Collection telemetry monitor that hooks into Node.js performance observer channels to calculate GC pause durations, frequency, and space growth in real time.

### File 1: `src/gc_telemetry_monitor.ts`

```typescript
import { PerformanceObserver, performance } from 'node:perf_hooks';
import v8 from 'node:v8';

export interface GcMetricsSummary {
    minorGcCount: number;
    majorGcCount: number;
    totalMinorDurationMs: number;
    totalMajorDurationMs: number;
    maxPauseMs: number;
    currentHeapUsageMb: number;
}

export class GarbageCollectionMonitor {
    private observer: PerformanceObserver;
    private minorCount = 0;
    private majorCount = 0;
    private totalMinorMs = 0;
    private totalMajorMs = 0;
    private maxPause = 0;

    constructor() {
        this.observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
                const duration = entry.duration;
                if (duration > this.maxPause) this.maxPause = duration;

                // Entry details from node:perf_hooks GC hooks
                // Kind 1: Scavenge (Minor GC), Kind 2: Mark-Sweep-Compact (Major GC)
                const detail = (entry as any).detail;
                const kind = detail ? detail.kind : 1;

                if (kind === 1 || entry.name.includes('scavenge')) {
                    this.minorCount++;
                    this.totalMinorMs += duration;
                } else {
                    this.majorCount++;
                    this.totalMajorMs += duration;
                    console.log(`[MAJOR GC ALERT] Mark-Sweep pause: ${duration.toFixed(2)} ms!`);
                }
            }
        });

        // Observe GC performance events
        this.observer.observe({ entryTypes: ['gc'] });
    }

    public getMetrics(): GcMetricsSummary {
        const heap = v8.getHeapStatistics();
        return {
            minorGcCount: this.minorCount,
            majorGcCount: this.majorCount,
            totalMinorDurationMs: Number(this.totalMinorMs.toFixed(2)),
            totalMajorDurationMs: Number(this.totalMajorMs.toFixed(2)),
            maxPauseMs: Number(this.maxPause.toFixed(2)),
            currentHeapUsageMb: Number((heap.used_heap_size / 1024 / 1024).toFixed(2))
        };
    }

    public printHeapSpaces(): void {
        console.log("-------------------------------------------------");
        console.log("V8 HEAP SPACE BREAKDOWN:");
        for (const space of v8.getHeapSpaceStatistics()) {
            const usedMb = (space.space_used_size / 1024 / 1024).toFixed(2);
            const totalMb = (space.space_size / 1024 / 1024).toFixed(2);
            console.log(`  - ${space.space_name.padEnd(20)}: ${usedMb.padStart(6)} MB / ${totalMb.padStart(6)} MB`);
        }
        console.log("-------------------------------------------------");
    }

    public stop(): void {
        this.observer.disconnect();
    }
}

async function runGcLab() {
    console.log('[LAB] Initializing V8 Garbage Collection Telemetry Engine...');
    const monitor = new GarbageCollectionMonitor();

    console.log('[WORKLOAD] Generating transient allocations to trigger Scavenger cycles...');
    for (let i = 0; i < 500000; i++) {
        // Transient young generation object allocations
        const obj = { id: i, payload: `DATA_ITEM_${i}`, timestamp: Date.now() };
        if (i % 100000 === 0) {
            // Keep some references alive to trigger promotion to Old Space
            (global as any)[`retained_${i}`] = obj;
        }
    }

    // Allow event loop to process GC metrics
    await new Promise((r) => setTimeout(r, 100));

    console.log("=================================================");
    console.log("GC TELEMETRY REPORT:");
    console.log(monitor.getMetrics());
    monitor.printHeapSpaces();
    console.log("=================================================");

    monitor.stop();
    console.log('✅ GC Telemetry Lab completed cleanly.');
}

runGcLab();
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
    src/gc_telemetry_monitor.ts

# 2. Run with verbose V8 GC tracing enabled
node \
    --trace-gc \
    --trace-gc-verbose \
    --max-old-space-size=256 \
    src/gc_telemetry_monitor.js

# 3. Analyze heap distribution from CLI with diagnostic snapshots
node --max-old-space-size=256 -e "
    const v8 = require('node:v8');
    console.table(v8.getHeapSpaceStatistics());
"
```

---

## 6. Detailed Sub-Components & Diagnostics

### V8 Semi-Space Pointer Allocator

* **Role & Function**: Manages the `top` and `limit` pointers in New Space, allowing object allocation in $< 3$ CPU assembly instructions without lock contention.
* **Inspection Command**:

  ```bash
  node --trace-opt-verbose src/gc_telemetry_monitor.js
  ```

### V8 Concurrent Sweeper Thread Manager

* **Role & Function**: Spawns background OS threads to unmap and reclaim memory pages from the OS kernel while the JavaScript main thread executes.
* **Inspection Command**:

  ```bash
  node --trace-concurrent-marking src/gc_telemetry_monitor.js
  ```

---

## References

### Official Documentation

* [V8 Garbage Collection: Trash Talk Series](https://v8.dev/blog/trash-talk) — Core V8 GC architecture.
* [V8 Concurrent Marking Architecture](https://v8.dev/blog/concurrent-marking) — Incremental and concurrent GC.
* [Node.js V8 Module Specification](https://nodejs.org/docs/latest/api/v8.html) — V8 APIs in Node.js.
* [Node.js Performance Hooks GC API](https://nodejs.org/docs/latest/api/perf_hooks.html#performance-observer-gc-events) — GC event hooks.
* [ECMAScript Memory Model Standard](https://tc39.es/ecma262/#sec-memory-model) — Language memory guarantees.

### Authoritative Engineering Blogs

* [Brendan Gregg: Memory Allocation & Linux Page Faults](https://www.brendangregg.com/) — Systems memory.
* [Matteo Collina: Eliminating Node.js Garbage Collection Pauses](https://noders.com/) — Low-latency design.
* [Netflix TechBlog: Tuning V8 Memory for Node.js Services](https://netflixtechblog.com/) — Enterprise GC tuning.
* [Cloudflare Engineering: V8 Isolates and Garbage Collection](https://blog.cloudflare.com/) — Isolate memory management.
* [Uber Engineering: Garbage Collection Tuning for High-QPS Microservices](https://www.uber.com/blog/) — GC optimization.

---

## 7. FinOps & Cloud Resource Cost Governance

*Proper V8 heap sizing prevents GC pause degradation and eliminates random cloud container restarts.*

### 1. Eliminating GC Pause Latency Cascades

When V8 heap usage nears the configured limit, Major Mark-Sweep GC frequency spikes from once every 5 minutes to several times per second, consuming 80%+ of total CPU. Configuring `--max-old-space-size` at $1.5\times$ the steady-state baseline eliminates GC thrashing, keeping p99 response times under 5ms.

### 2. Sizing Containers for Minimal RSS Footprint

Resident Set Size (RSS) represents the physical RAM mapped by the OS kernel, including V8 heap, C++ off-heap buffers, and binary code pages. Keeping V8 Old Space at 384MB ensures total container RSS stays reliably under 512MB, allowing maximum container density on Kubernetes worker nodes.

---

## 8. Troubleshooting, Diagnostic Workflows & Common Anti-Patterns

### Common Anti-Patterns

1. **Invoking `global.gc()` in Production**:

   * *Anti-Pattern*: Calling `global.gc()` inside HTTP request handlers to "clean up memory". This forces a synchronous, multi-millisecond stop-the-world Major GC freeze on every request.
   * *Fix*: Allow V8's automated heuristics to schedule incremental and concurrent GC passes naturally.

2. **Allocating Large Arrays with Holes (Sparse Arrays)**:

   * *Anti-Pattern*: Writing `const a = []; a[1000000] = 1;`. Sparse arrays force V8 to drop fast packed element backing stores and transition to slow dictionary-mode hash tables.
   * *Fix*: Pre-allocate dense arrays (`new Array(1000000).fill(0)`) or use TypedArrays (`new Int32Array(1000000)`).

3. **Retaining Large Closures in Event Handlers**:

   * *Anti-Pattern*: Declaring event listeners inside functions holding large local variables. The closure retains the entire outer scope in memory.
   * *Fix*: Extract handlers into standalone methods or nullify unused large variables before binding listeners.
