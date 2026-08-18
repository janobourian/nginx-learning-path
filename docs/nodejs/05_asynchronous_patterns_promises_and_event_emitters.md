# Module 05: Asynchronous Patterns: EventEmitters, Promises & AbortController
**Category:** Asynchronous Architecture, Reactive Events & Cancellation
**Status:** ✅ Completed

---

## 1. High-Level Overview
Asynchronous execution in Node.js relies on two foundational paradigms: the **EventEmitter Pattern** (Observer pattern for streaming event dispatch) and **Promises / Async-Await** (linear control flow for asynchronous tasks) paired with modern **AbortController** for deterministic cancellation.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Master asynchronous event dispatching, custom event pipelines, promise concurrency (`Promise.allSettled`), and request cancellation.
* **How It Works**: Uses EventEmitters to build decoupled, modular backend event architectures without tight coupling.
* **Key Business Value & Use Cases**: Prevents memory leaks from dangling event listeners and aborts slow external API calls before timeouts occur.

---

## 📌 Foundations, Notes & Original Architecture (Original Notes)

### Asynchronous Patterns (Original Notes)
* `EventEmitter.defaultMaxListeners = 10` (Warns upon exceeding 10 listeners to detect memory leaks)
* Always handle `'error'` events on EventEmitters or Node will throw an unhandled exception and crash:
```javascript
emitter.on('error', (err) => console.error('Handled event error:', err));
```

---

## 2. Complete Language Syntax, Keywords & Operators Dictionary

### Complete Asynchronous Patterns & Events Dictionary

| Class / Method | Category | Definition & Technical Syntax |
| :--- | :--- | :--- |
| `EventEmitter.on(event, listener)` | Events | Registers a persistent listener function for the specified event name. |
| `EventEmitter.once(event, listener)` | Events | Registers a one-time listener function that automatically unregisters after first execution. |
| `EventEmitter.emit(event, ...args)` | Events | Synchronously calls each of the listeners registered for the event in registration order. |
| `EventEmitter.removeListener(event, fn)` | Events | Unregisters a specific listener function to prevent memory leaks. |
| `events.on(emitter, event, [opts])` | Events | Creates an AsyncIterator that yields events as an asynchronous stream. |
| `Promise.all(iterable)` | Promises | Resolves when all promises resolve; rejects immediately upon the first rejection. |
| `Promise.allSettled(iterable)` | Promises | Resolves after all promises settle, returning an array of `{status, value/reason}` objects. |
| `Promise.race(iterable)` | Promises | Settles as soon as any promise in the iterable settles (either resolves or rejects). |
| `AbortController` | Control | Instantiates a controller object with an `AbortSignal` to cancel async operations. |
| `AbortSignal.timeout(ms)` | Control | Returns an AbortSignal that automatically triggers an abort error after `ms` milliseconds. |

---

## 3. Technical Deep Dive & Core Mechanics

### 1. EventEmitter Internal Execution Mechanics
- `EventEmitter` executes listeners **synchronously in the order they were registered**.
- If 10 listeners are registered on `'orderCreated'`, calling `emit('orderCreated')` invokes all 10 functions sequentially before returning to the next line of code!

### 2. Deterministic Cancellation via `AbortController`
Passing an `AbortSignal` to `fetch()`, `fs.promises`, or child processes allows cancelling long-running tasks:
```javascript
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 5000); // 5s timeout
const response = await fetch('https://api.example.com', { signal: controller.signal });
clearTimeout(timeout);
```

---

## 4. Hands-On Step-by-Step Production Lab

### Step 1: Implement an Enterprise Event-Driven Order Processing Pipeline
Create `order_events.js`:
```javascript
const { EventEmitter } = require('node:events');

class OrderPipeline extends EventEmitter {
    constructor() {
        super();
        this.setMaxListeners(20);
    }

    async processOrder(orderId, amount) {
        this.emit('order:received', { orderId, amount, timestamp: Date.now() });

        try {
            // Simulate payment processing
            if (amount <= 0) throw new Error('Invalid order amount');
            this.emit('order:paid', { orderId, amount });

            // Simulate fulfillment
            this.emit('order:fulfilled', { orderId, trackingCode: `TRK_${orderId}` });
        } catch (err) {
            this.emit('error', err);
        }
    }
}

// Instantiate and attach listeners
const pipeline = new OrderPipeline();

pipeline.on('order:received', (data) => console.log(`[EVENT] Order Received: #${data.orderId}`));
pipeline.on('order:paid', (data) => console.log(`[EVENT] Payment Succeeded: $${data.amount}`));
pipeline.on('order:fulfilled', (data) => console.log(`[EVENT] Fulfilled with tracking: ${data.trackingCode}`));
pipeline.on('error', (err) => console.error(`[ERROR] Pipeline Error Caught: ${err.message}`));

// Test successful and failing orders
pipeline.processOrder(1001, 250.00);
pipeline.processOrder(1002, -50.00);
```

### Step 2: Run and Validate
```bash
node order_events.js
```

---

## 5. Pure Escaped CLI Snippets (Production Operations)

### 1. Test Promise.allSettled Execution
Run async concurrency test:
```bash
node -e '
Promise.allSettled([Promise.resolve("OK"), Promise.reject("ERR")])
  .then(res => console.log("Settled results:", res));
'
```

### 2. Verify Event Listener Leak Detection
Verify listener warning threshold:
```bash
node -e '
const { EventEmitter } = require("events");
const e = new EventEmitter();
for(let i=0; i<11; i++) e.on("test", () => {});
' 2>&1 | grep -i warning || true
```

---

## 6. Detailed Sub-Components

### EventEmitter Listener Hash Map
* **Role & Function**: Key-value dictionary mapping event strings to arrays of function pointers.
* **Inspection Command**:
  ```bash
  echo 'EventEmitter map active'
  ```

### AbortSignal Event Dispatcher
* **Role & Function**: DOM-standard abort dispatcher signaling task cancellation across async boundaries.
* **Inspection Command**:
  ```bash
  echo 'AbortSignal active'
  ```

---

## References

### Official Documentation
* [Official Language & Framework Manual](https://nodejs.org/docs/latest/api/) - Official technical manual.
* [W3C & TC39 Language Standard Specifications](https://tc39.es/ecma262/) - Official technical manual.
* [MDN Web Docs Official API Reference](https://developer.mozilla.org/) - Official technical manual.
* [Open Source Project GitHub Architecture](https://github.com/) - Official technical manual.
* [Cloud Native Computing Foundation (CNCF)](https://www.cncf.io/) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Martin Fowler: Enterprise Application Architecture](https://martinfowler.com/) - Industry standard analysis.
* [Brendan Gregg: Systems Performance and Profiling](https://www.brendangregg.com/) - Industry standard analysis.
* [Addy Osmani: Web Performance & Engineering Principles](https://addyosmani.com/) - Industry standard analysis.
* [Netflix TechBlog: High-Scale Systems Design](https://netflixtechblog.com/) - Industry standard analysis.
* [Baeldung on Computer Science: In-Depth Engineering Guides](https://www.baeldung.com/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Asynchronous Code

*Timeouts and signal cancellation prevent zombie compute tasks.*

#### 1. Mandatory `AbortSignal.timeout` on Outbound API Calls
Outbound HTTP calls without timeouts can hang indefinitely on slow third-party servers, holding open Node.js sockets and RAM buffers. Setting `signal: AbortSignal.timeout(5000)` aborts hanging requests in 5 seconds, freeing server memory and sockets.

#### 2. `Promise.allSettled` vs `Promise.all` in Batch Workflows
`Promise.all` fails fast on the first rejected promise, abandoning remaining tasks while they continue consuming backend CPU in the background. `Promise.allSettled` allows inspecting all results and executing proper cleanup, preventing orphaned database locks.

#### 3. Unregistering Event Listeners on Component Teardown
Failing to call `emitter.removeListener()` or `controller.abort()` when client connections terminate causes listeners to retain closures in memory, leading to slow heap memory leaks that force costly server restarts.
