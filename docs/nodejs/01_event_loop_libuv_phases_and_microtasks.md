# Module 01: The Node.js Event Loop, Libuv Phases & Microtasks

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Concurrency Internals, Libuv Thread Pool & Event Scheduling

---

## 1. Demystifying the Single-Threaded Myth

A frequent misconception in software engineering is: *"Node.js is completely single-threaded."*

### The Reality:
- **JavaScript Execution is Single-Threaded**: Userland JavaScript runs on a single V8 main thread.
- **The Node.js Runtime is Multi-Threaded**: Node.js is backed by **libuv**, which manages a background **Worker Thread Pool** (default: 4 C threads) and leverages OS kernel asynchronous notification mechanisms (**epoll** on Linux, **kqueue** on macOS, and **IOCP** on Windows).

---

## 2. The 6 Phases of the Libuv Event Loop

Every rotation ("tick") of the Libuv Event Loop progresses through **six distinct, sequential phases**:

```
┌─────────────────────────────────────────────────────────────┐
│                 The 6 Libuv Event Loop Phases               │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │      1. Timers       │ ◄── Executes callbacks from       │
│  │                      │     `setTimeout` & `setInterval`  │
│  └──────────┬───────────┘                                   │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │ 2. Pending Callbacks │ ◄── I/O callbacks deferred from   │
│  │                      │     previous loop iteration       │
│  └──────────┬───────────┘                                   │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │   3. Idle, Prepare   │ ◄── Internal libuv housekeeping   │
│  └──────────┬───────────┘                                   │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │       4. Poll        │ ◄── Retrieves new I/O events;     │
│  │ (epoll / kqueue / IO)│     executes I/O callbacks; blocks│
│  └──────────┬───────────┘     if no other tasks are pending │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │       5. Check       │ ◄── Executes `setImmediate()`     │
│  │                      │     callbacks                     │
│  └──────────┬───────────┘                                   │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │  6. Close Callbacks  │ ◄── Socket close, handle teardown │
│  └──────────────────────┘     e.g. `socket.on('close')`     │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. The Microtask Queues: `process.nextTick()` & Promises

Microtasks do **not** belong to any of the 6 Libuv phases. 

Instead, the **Microtask Queues are executed immediately after the current JavaScript operation finishes, between EVERY phase of the event loop**:

```
Microtask Priority Hierarchy:
[Current JS Function Completes]
       │
       ▼
[1. process.nextTick Queue] (Executed FIRST until completely empty!)
       │
       ▼
[2. Promise Microtask Queue] (`Promise.then()`, `async/await`, `queueMicrotask()`)
       │
       ▼
[Next Libuv Phase in Event Loop begins]
```

### The Starvation Hazard with `process.nextTick()`:

Because `process.nextTick()` drains completely before the event loop advances to the next phase, a recursive `process.nextTick()` loop will **permanently starve the event loop**, freezing all I/O, timers, and HTTP requests:

```javascript
// ❌ DANGEROUS: Starves the event loop! No HTTP requests or timers will ever fire!
function recursiveStarvation() {
  process.nextTick(recursiveStarvation);
}
```

---

## 4. Dissecting Execution Order (The Ultimate Execution Puzzle)

Consider this canonical script:

```javascript
// test-order.js
import fs from 'node:fs';

console.log('1. Synchronous Global Code');

setTimeout(() => {
  console.log('2. setTimeout (0ms) in Timers Phase');
}, 0);

setImmediate(() => {
  console.log('3. setImmediate in Check Phase');
});

Promise.resolve().then(() => {
  console.log('4. Promise Microtask');
});

process.nextTick(() => {
  console.log('5. process.nextTick Microtask');
});

fs.readFile(new URL(import.meta.url), () => {
  console.log('6. I/O Callback in Poll Phase');

  setTimeout(() => console.log('7. Nested setTimeout in Timers Phase'), 0);
  setImmediate(() => console.log('8. Nested setImmediate in Check Phase'));
  process.nextTick(() => console.log('9. Nested nextTick'));
});

console.log('10. Synchronous Global Code Finished');
```

### Output Breakdown:
```text
1. Synchronous Global Code
10. Synchronous Global Code Finished
5. process.nextTick Microtask      ◄── Microtask (nextTick takes precedence)
4. Promise Microtask               ◄── Microtask (Promises drain next)
2. setTimeout (0ms) in Timers Phase ◄── Timers Phase
3. setImmediate in Check Phase     ◄── Check Phase
6. I/O Callback in Poll Phase      ◄── Poll Phase (I/O resolved)
9. Nested nextTick                 ◄── Microtask immediately after I/O callback
8. Nested setImmediate             ◄── Check Phase comes IMMEDIATELY after Poll!
7. Nested setTimeout               ◄── Next tick Timers Phase
```

*Crucial Insight:* Inside an I/O callback (`fs.readFile`), `setImmediate` is **always guaranteed to execute before `setTimeout(..., 0)`** because the `Check` phase immediately follows the `Poll` phase in the Libuv cycle!

---

## 5. The Libuv Worker Thread Pool (`UV_THREADPOOL_SIZE`)

While network sockets (HTTP, TCP, UDP) use OS non-blocking kernel polling (`epoll`/`kqueue`) and **never consume thread pool threads**, certain operations cannot be performed asynchronously by OS kernels and are delegated to the **Libuv Thread Pool**:

### Operations Using the Libuv Thread Pool:
1. **File System I/O**: `node:fs` asynchronous calls (`fs.readFile`, `fs.writeFile`, `fs.stat`).
2. **DNS Lookups**: `dns.lookup()` (uses blocking `getaddrinfo(3)` C system call).
3. **CPU-Bound Cryptography**: `crypto.pbkdf2()`, `crypto.scrypt()`, `crypto.randomBytes()`.
4. **Compression**: `node:zlib` methods.

### Scaling the Thread Pool for High-Load Microservices:

By default, the thread pool size is **4 threads**. If your app performs 10 concurrent file reads or password hashes, 6 requests will wait in queue!

Increase the thread pool size via the environment variable before Node.js boots:

```bash
# Allocate 16 background worker threads (Max: 1024):
UV_THREADPOOL_SIZE=16 node src/server.js
```

---

## Troubleshooting & Best Practices

1. **`dns.lookup` vs `dns.resolve`**
   - `dns.lookup()`: Uses the OS `getaddrinfo` system call, which runs synchronously on the **Libuv Thread Pool**. High DNS load can exhaust the thread pool and stall file I/O!
   - `dns.resolve()`: Uses **c-ares** over asynchronous network sockets, completely bypassing the thread pool!

2. **Prefer `setImmediate()` over `setTimeout(fn, 0)`**
   `setImmediate()` is specifically scheduled for the `Check` phase of the current loop tick, avoiding timer heap registration and minimum 1ms timer resolution overhead.
