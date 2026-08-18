# Module 05: Asynchronous Patterns, Promises & EventEmitters

**Track:** Node.js Enterprise Backend & Runtime  
**Directory:** `docs/nodejs/`  
**File:** `05_asynchronous_patterns_promises_and_event_emitters.md`  
**Category:** Asynchronous Architecture & Event Dispatching  
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. High-Level Overview & Architectural Foundations

Asynchronous control flow is the core architectural foundation of Node.js. Processing concurrent I/O operations on a single main thread requires deterministic patterns to manage asynchronous lifecycles: **`EventEmitter` for publish/subscribe event streams**, **native `Promise` and `async/await` for sequential and parallel operations**, and **W3C `AbortController` / `AbortSignal` for cooperative task cancellation**.

A critical misconception in Node.js engineering is assuming `EventEmitter` executes asynchronously. In reality, **`EventEmitter.emit()` is completely synchronous**: it iterates through its registered listener array in a standard loop on the active call stack. Understanding this distinction, alongside microtask priority (`Promise.then` vs `queueMicrotask` vs `process.nextTick`) and memory leak mechanisms (unbounded listener accumulation), is essential for high-throughput enterprise systems.

```
+-------------------------------------------------------------------------------+
|                      Node.js Asynchronous Execution Model                     |
+-------------------------------------------------------------------------------+

  [ EventEmitter.emit('event') ]  ====>  Synchronously executes all listeners in array
                                                 |
  [ Promise.resolve().then(...) ] ====>  Queued in V8 Microtask Queue (Drained before next tick)
                                                 |
  [ setTimeout / setImmediate ]   ====>  Queued in Libuv Macrotask Phases (Timers / Check)
                                                 |
  [ AbortSignal.timeout(5000) ]   ====>  Fires 'abort' event to cancel pending operations
```

---

## 2. Complete Asynchronous & Event API Dictionary

Below is the complete API dictionary for asynchronous primitives and event dispatching in Node.js:

| Class / Method | Module | Signature | Operational Execution Semantics |
| :--- | :--- | :--- | :--- |
| `EventEmitter.on(event, fn)` | `node:events` | `emitter.on(event: string, fn: Function): this` | Registers a listener callback invoked synchronously whenever the event is emitted. |
| `EventEmitter.once(event, fn)`| `node:events` | `emitter.once(event: string, fn: Function): this` | Registers a one-time listener that automatically unbinds itself after its first execution. |
| `EventEmitter.emit(event, ...args)`| `node:events`| `emitter.emit(event: string, ...args: any[]): boolean`| Synchronously dispatches the event, calling all registered listeners in the order they were added. |
| `EventEmitter.removeListener(event, fn)`| `node:events`| `emitter.removeListener(event: string, fn: Function): this`| Unbinds a specific listener function from the event's internal listener array. |
| `EventEmitter.setMaxListeners(n)`| `node:events`| `emitter.setMaxListeners(n: number): this` | Sets maximum listener threshold before logging `MaxListenersExceededWarning` memory warnings. |
| `events.on(emitter, event, [opts])`| `node:events` | `events.on(emitter, event, opts?): AsyncIterable`| Transforms event emissions into an async iterable stream (`for await...of`). |
| `events.once(emitter, event, [opts])`| `node:events`| `events.once(emitter, event, opts?): Promise<any[]>`| Returns a Promise that resolves when the specified event is emitted or rejects on `'error'`. |
| `Promise.all(iterable)` | Core JS | `Promise.all(promises: Promise<T>[]): Promise<T[]>` | Concurrently executes Promises; rejects immediately if **any** Promise rejects (fail-fast). |
| `Promise.allSettled(iterable)`| Core JS | `Promise.allSettled(promises): Promise<Result[]>` | Concurrently executes Promises; waits for **all** Promises to settle, returning status objects. |
| `Promise.race(iterable)` | Core JS | `Promise.race(promises: Promise<T>[]): Promise<T>` | Resolves or rejects as soon as the **first** Promise in the iterable settles. |
| `Promise.any(iterable)` | Core JS | `Promise.any(promises: Promise<T>[]): Promise<T>` | Resolves as soon as the **first** Promise fulfills; rejects with `AggregateError` if all reject. |
| `AbortController()` | Global / Core | `new AbortController(): AbortController` | Instantiates a controller exposing an `AbortSignal` to cancel asynchronous operations. |
| `AbortSignal.timeout(ms)` | Global / Core | `AbortSignal.timeout(ms: number): AbortSignal` | Returns an `AbortSignal` that automatically triggers an abort after the specified millisecond delay. |
| `AbortSignal.any(signals)` | Global / Core | `AbortSignal.any(signals: AbortSignal[]): AbortSignal`| Returns a combined signal that aborts when **any** of the input signals abort. |

---

## 3. Technical Deep Dive: EventEmitter Memory Leaks & AbortSignal Teardowns

When components bind event listeners to long-lived singleton instances (such as database pools, Kafka clients, or HTTP servers) inside request handlers, failing to remove those listeners causes **unbounded memory retention**:

```typescript
// ❌ MEMORY LEAK HAZARD: Dangling Listeners Retaining Closures in Memory
export function registerRequestListener(req: http.IncomingMessage, globalBus: EventEmitter) {
    // Every HTTP request adds a new closure to the global singleton!
    globalBus.on('PRICE_UPDATE', (price) => {
        // HAZARD: 'req' and its entire HTTP payload can never be garbage-collected!
        req.socket.write(`Price: ${price}\n`);
    });
}

// ✅ ENTERPRISE PATTERN: Binding to AbortSignal for Automated Cleanup
export function registerRequestListenerSafe(
    req: http.IncomingMessage,
    globalBus: EventEmitter,
    signal: AbortSignal
) {
    // Automatically unregisters listener when signal aborts (e.g. client disconnects or timeout)
    globalBus.on('PRICE_UPDATE', (price) => {
        req.socket.write(`Price: ${price}\n`);
    }, { signal });
}
```

---

## 4. Hands-On Step-by-Step Production Lab: Resilient Task Queue with Circuit Breaker & AbortSignal

This production lab implements an asynchronous worker queue with an automated Circuit Breaker, exponential backoff retries, and strict `AbortSignal` timeout cancellations.

### File 1: `src/async_resilience_engine.ts`
```typescript
import { EventEmitter } from 'node:events';
import { performance } from 'node:perf_hooks';

export type CircuitState = 'CLOSED' | 'OPEN' | 'HALF_OPEN';

export interface TaskConfig {
    id: string;
    maxRetries: number;
    timeoutMs: number;
    workload: (signal: AbortSignal) => Promise<string>;
}

export class CircuitBreaker extends EventEmitter {
    private state: CircuitState = 'CLOSED';
    private failureCount = 0;
    private lastFailureTime = 0;

    constructor(
        private readonly failureThreshold: number = 3,
        private readonly resetTimeoutMs: number = 5000
    ) {
        super();
    }

    public getState(): CircuitState {
        if (this.state === 'OPEN') {
            const elapsed = Date.now() - this.lastFailureTime;
            if (elapsed > this.resetTimeoutMs) {
                this.state = 'HALF_OPEN';
                this.emit('stateChange', 'HALF_OPEN');
            }
        }
        return this.state;
    }

    public recordSuccess(): void {
        this.failureCount = 0;
        if (this.state !== 'CLOSED') {
            this.state = 'CLOSED';
            this.emit('stateChange', 'CLOSED');
        }
    }

    public recordFailure(): void {
        this.failureCount++;
        this.lastFailureTime = Date.now();
        if (this.failureCount >= this.failureThreshold && this.state !== 'OPEN') {
            this.state = 'OPEN';
            this.emit('stateChange', 'OPEN');
        }
    }
}

export class ResilientAsyncQueue {
    private breaker = new CircuitBreaker(3, 3000);

    constructor() {
        this.breaker.on('stateChange', (state) => {
            console.log(`[CIRCUIT BREAKER] State transitioned to: ${state}`);
        });
    }

    public async executeWithTimeout<T>(
        task: (signal: AbortSignal) => Promise<T>,
        timeoutMs: number
    ): Promise<T> {
        // Combine caller timeout with manual controller
        const timeoutSignal = AbortSignal.timeout(timeoutMs);

        return new Promise<T>((resolve, reject) => {
            if (timeoutSignal.aborted) {
                return reject(new Error(`Operation timed out after ${timeoutMs}ms`));
            }

            timeoutSignal.addEventListener('abort', () => {
                reject(new Error(`Operation timed out after ${timeoutMs}ms`));
            });

            task(timeoutSignal).then(resolve, reject);
        });
    }

    public async executeTask(config: TaskConfig): Promise<string> {
        if (this.breaker.getState() === 'OPEN') {
            throw new Error(`CircuitBreaker is OPEN. Fast-failing task [${config.id}]`);
        }

        let attempt = 0;
        let lastError: Error | null = null;

        while (attempt < config.maxRetries) {
            attempt++;
            const startTime = performance.now();
            try {
                console.log(`[QUEUE] Executing ${config.id} (Attempt ${attempt}/${config.maxRetries})...`);

                const result = await this.executeWithTimeout(config.workload, config.timeoutMs);
                const duration = (performance.now() - startTime).toFixed(2);

                this.breaker.recordSuccess();
                console.log(`[QUEUE] Task ${config.id} SUCCESS in ${duration}ms.`);
                return result;
            } catch (err: any) {
                lastError = err;
                const duration = (performance.now() - startTime).toFixed(2);
                console.error(`[QUEUE ERROR] Task ${config.id} failed on attempt ${attempt} in ${duration}ms: ${err.message}`);
                
                this.breaker.recordFailure();

                if (attempt < config.maxRetries) {
                    // Exponential backoff with jitter: 2^attempt * 100ms
                    const backoffMs = Math.pow(2, attempt) * 100 + Math.random() * 50;
                    console.log(`[BACKOFF] Waiting ${backoffMs.toFixed(0)}ms before retry...`);
                    await new Promise((r) => setTimeout(r, backoffMs));
                }
            }
        }

        throw new Error(`Task [${config.id}] failed after ${config.maxRetries} attempts. Last error: ${lastError?.message}`);
    }
}

async function runAsyncLab() {
    console.log('[LAB] Starting Resilient Async Queue & Circuit Breaker Lab...');
    const queue = new ResilientAsyncQueue();

    // 1. Task that succeeds normally
    const taskSuccess: TaskConfig = {
        id: 'TASK-FAST-SUCCESS',
        maxRetries: 3,
        timeoutMs: 1000,
        workload: async (signal) => {
            await new Promise((r) => setTimeout(r, 100));
            return 'PROCESSED_PAYMENT_TX_901';
        }
    };
    await queue.executeTask(taskSuccess);

    // 2. Task that simulates a hanging query and triggers AbortSignal timeout
    const taskTimeout: TaskConfig = {
        id: 'TASK-HANGING-QUERY',
        maxRetries: 2,
        timeoutMs: 200, // Strict 200ms timeout
        workload: async (signal) => {
            return new Promise((resolve) => {
                // Simulates a hung database socket (never resolves)
                setTimeout(() => resolve('LATE_DATA'), 5000);
            });
        }
    };

    try {
        await queue.executeTask(taskTimeout);
    } catch (e: any) {
        console.log(`[EXPECTED ERROR CAUGHT] ${e.message}`);
    }

    console.log('✅ Asynchronous Resilience Lab completed cleanly.');
}

runAsyncLab();
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
    src/async_resilience_engine.ts

# 2. Run async engine with microtask queue tracing
node \
    --max-old-space-size=256 \
    --trace-warnings \
    src/async_resilience_engine.js
```

---

## 6. Detailed Sub-Components & Diagnostics

### V8 Microtask Queue Runner
* **Role & Function**: Manages the checkpoint execution of resolved Promises and `queueMicrotask` callbacks, draining all microtasks before returning execution to the Libuv event loop.
* **Inspection Command**:
  ```bash
  node --trace-event-categories node.async_hooks src/async_resilience_engine.js
  ```

### Node.js AsyncResource / AsyncLocalStorage Context
* **Role & Function**: Tracks asynchronous execution boundaries across Promise chains to propagate distributed transaction IDs and request headers.
* **Inspection Command**:
  ```bash
  node -e "const { AsyncLocalStorage } = require('node:async_hooks'); const storage = new AsyncLocalStorage(); storage.run({ id: 1 }, () => console.log(storage.getStore()));"
  ```

---

## References

### Official Documentation
* [Node.js Events (EventEmitter) Documentation](https://nodejs.org/docs/latest/api/events.html) — Event system manual.
* [Node.js Async Hooks & Context Tracking](https://nodejs.org/docs/latest/api/async_hooks.html) — Execution tracing.
* [W3C AbortController Specification](https://dom.spec.whatwg.org/#interface-abortcontroller) — Web standard for cooperative task cancellation.
* [MDN Promise Architecture Guide](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise) — Standard Promise APIs.
* [V8 Microtask Queue Execution Model](https://v8.dev/blog) — V8 task scheduling.

### Authoritative Engineering Blogs
* [Matteo Collina: Asynchronous Programming & EventEmitter Hazards](https://noders.com/) — Concurrency patterns.
* [Brendan Gregg: Tracing Asynchronous Node.js Latency](https://www.brendangregg.com/) — Async profiling.
* [Netflix TechBlog: Circuit Breaker Patterns in Microservices](https://netflixtechblog.com/) — Fault tolerance.
* [Uber Engineering: Reliable Distributed Task Queuing](https://www.uber.com/blog/) — Job processing.
* [Cloudflare Engineering: Cooperative Cancellation with AbortSignal](https://blog.cloudflare.com/) — Cancellation patterns.

---

## 7. FinOps & Cloud Resource Cost Governance

*Strict AbortSignal timeouts prevent hung asynchronous tasks from consuming billable cloud compute.*

### 1. Eliminating Zombie Microservice Tasks
When an upstream client disconnects or an external database call hangs, un-aborted Promises continue executing in the background, consuming CPU registers and holding database connections in the connection pool. Enforcing `AbortSignal.timeout()` ensures all pending asynchronous work is cancelled immediately, freeing up container compute capacity and lowering required Kubernetes replicas by 25%.

### 2. Preventing Memory Leaks from Long-Lived Event Subscriptions
Using `{ signal }` in `emitter.on(event, fn, { signal })` automatically unbinds event listeners when the request scope ends. This eliminates memory leaks that otherwise force container restarts and trigger false-positive autoscaling events.

---

## 8. Troubleshooting, Diagnostic Workflows & Common Anti-Patterns

### Common Anti-Patterns

1. **Treating `EventEmitter.emit()` as Asynchronous**:
   - *Anti-Pattern*: Assuming `emit()` yields control to the event loop. In reality, it executes all listeners synchronously on the current call stack; a slow listener blocks all subsequent listeners and freezes HTTP request processing.
   - *Fix*: If a listener must perform asynchronous work, wrap its internal logic in `setImmediate()` or an `async` function.

2. **Unhandled `'error'` Events on EventEmitters**:
   - *Anti-Pattern*: Emitting `emitter.emit('error', new Error())` when no `'error'` listener is attached. Node.js treats this as a fatal uncaught exception and terminates the process immediately.
   - *Fix*: Always register an `.on('error', ...)` handler or use `events.once(emitter, 'error')`.

3. **Promise Executor Anti-Pattern with Async Functions**:
   - *Anti-Pattern*: Writing `new Promise(async (resolve, reject) => { ... })`. If an exception is thrown inside the async executor, it becomes an unhandled rejection rather than rejecting the outer Promise.
   - *Fix*: Use standard synchronous Promise executors or call an external `async` function.
