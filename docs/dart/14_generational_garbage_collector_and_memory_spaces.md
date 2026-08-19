# Module 14: Generational Garbage Collection & Memory Management

**Track:** Dart — Language & VM Architecture
**Category:** Memory Architecture, Garbage Collection & Low-Latency Runtimes

---

## 1. The Generational Garbage Collection Hypothesis

The Dart Garbage Collector is engineered specifically for low-latency interactive UI (Flutter) and high-throughput server runtimes. It is built on the **Weak Generational Hypothesis**:

> *"Most allocated objects in computer programs die very quickly after creation (short lifespans)."*

In UI frameworks and API microservices, thousands of short-lived objects (e.g. temporary calculation variables, closures, intermediate widget nodes, JSON tokens) are allocated during a single frame or request and become unreachable within milliseconds.

---

## 2. The Two Generations: New Space vs Old Space

The Dart VM divides its heap memory into **two distinct spaces**:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           Dart Isolate Heap                             │
│                                                                         │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────┐  │
│  │     New Space (Young Gen)       │  │     Old Space (Old Gen)      │  │
│  │  - Size: 1MB – 32MB             │  │  - Size: 100MB – 4GB+        │  │
│  │  - Semi-Space Copying Scavenger │  │  - Concurrent Mark-Sweep     │  │
│  │  - Pause Time: < 0.5 ms!        │  │  - Sliding Compactor         │  │
│  └────────────────┬────────────────┘  └──────────────────────────────┘  │
│                   │ (Survives 2 GC Cycles)           ▲                  │
│                   └──────────────────────────────────┘                  │
│                                  Promotion                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. New Space & The Semi-Space Copying Scavenger

The **New Space** is split into two equal memory regions: **From-Space** (active allocation) and **To-Space** (inactive reserve).

### The Scavenging Cycle

1. When From-Space fills up, the VM initiates a **Scavenge**.
2. The scavenger starts from root pointers (stack frames, CPU registers) and copies all **reachable (live) objects** into To-Space.
3. All dead, unreachable objects left behind in From-Space are **instantly wiped in a single O(1) pointer reset**.
4. The roles of From-Space and To-Space are swapped.

Because only surviving objects are copied (and most objects are dead), a Scavenger cycle completes in **under 0.5 milliseconds**, easily fitting within a 16.6ms (60fps) or 8.3ms (120fps) frame budget!

### Object Promotion Policy

If an object in New Space survives **two consecutive scavenger cycles**, it is promoted to **Old Space**.

---

## 4. Old Space: Concurrent Mark-Sweep & Compaction

The **Old Space** holds long-lived objects (e.g. user session caches, database connection pools, singleton services).

Because Old Space is large, stopping the thread to clean it would cause visible frame stutter (jank).

### The Concurrent Collector

1. **Concurrent Marking**: A background thread traverses and marks live objects in Old Space **while the main Dart isolate continues executing user code**.
2. **Concurrent Sweeping**: Background threads reclaim the memory of unmarked dead objects.
3. **Sliding Compactor (Mark-Compact)**: Periodically defragments fragmented memory blocks by sliding live objects into contiguous memory blocks.

---

## 5. Isolate Memory Independence (Zero Global Stop-The-World)

In traditional runtimes (Java JVM, Go, Node.js), a heavy GC cycle on one thread can trigger a global **Stop-The-World (STW)** pause across the entire process.

In Dart:

- **Each Isolate has its own independent Garbage Collector.**
- If a background worker isolate triggers a heavy Old-Space GC cycle, the **Main UI Isolate continues running smoothly at 120fps with ZERO interruption!**

```text
Isolate GC Independence:
Worker Isolate #2:  ──[Collecting Old Space (10ms)]──► (Main UI is unaffected!)
Main UI Isolate:    ──[Frame 1 (60fps)]──[Frame 2 (60fps)]──[Frame 3 (60fps)]──►
```

---

## 6. Diagnosing Memory Leaks in Dart

Common causes of memory leaks in Dart:

1. **Unclosed `StreamSubscription`**: Subscriptions holding references to component closures.
2. **Static / Global Collections**: Appending items to a global `List` or `Map` without eviction.
3. **Callbacks registered with persistent Singletons**.

### Inspecting Heap Allocations with DevTools

```bash

# Launch application with DevTools observer
dart --observe bin/main.dart
```

In the **Dart DevTools Memory View**:

1. Take a **Heap Snapshot** at Time A.
2. Perform a workflow (e.g. open/close project 10 times).
3. Take a **Heap Snapshot** at Time B and inspect the **Diff**.
4. Filter by count to identify objects that failed to be collected by the Scavenger.

---

## Troubleshooting & Best Practices

1. **Avoid Unnecessary Object Allocations in Hot Loops**
   Avoid creating temporary objects inside high-frequency loops (e.g. `onMouseMove` or per-byte stream parsing). Reuse byte buffers or use Dart 3.3+ `extension type` zero-cost primitives.

2. **Explicitly Nullify References in Long-Lived Collections**
   When removing items from custom data structures or ring buffers, overwrite the slot with `null` so the Scavenger knows the object is no longer referenced.
