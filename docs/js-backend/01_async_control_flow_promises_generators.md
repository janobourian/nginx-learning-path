# Module 01: Asynchronous Control Flow — Promises, Generators & Concurrency Pools

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Asynchronous Architecture, Concurrency Control & Generators

---

## 1. The Promise Combinator Suite

Modern JavaScript provides five native Promise combinators for managing concurrent asynchronous workflows:

```
┌─────────────────────────────────────────────────────────────┐
│                 The 5 Native Promise Combinators            │
├────────────────────┬────────────────────────────────────────┤
│ **`Promise.all`**  │ Waits for ALL to succeed. Fails fast   │
│                    │ on the first rejection.                │
├────────────────────┼────────────────────────────────────────┤
│ **`Promise.allSettled`**│ Waits for ALL to finish (either   │
│                    │ fulfilled or rejected). Never rejects! │
├────────────────────┼────────────────────────────────────────┤
│ **`Promise.race`** │ Resolves or rejects as soon as the     │
│                    │ FIRST promise settles.                 │
├────────────────────┼────────────────────────────────────────┤
│ **`Promise.any`**  │ Resolves as soon as the FIRST promise  │
│                    │ SUCCEEDS (Ignores individual errors).  │
├────────────────────┼────────────────────────────────────────┤
│ **`Promise.withResolvers`**│ Creates an uncompleted promise │
│ (ES2024 Standard)  │ with extracted `{ promise, resolve,    │
│                    │ reject }` handles without boilerplate! │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. ES2024 `Promise.withResolvers()`

Instead of the cumbersome `new Promise((res, rej) => ...)` wrapper, **`Promise.withResolvers()`** extracts the resolution functions directly:

```javascript
// Bridging Event Listeners to a Promise cleanly:
export function waitForServerEvent(emitter, eventName, timeoutMs = 5000) {
  const { promise, resolve, reject } = Promise.withResolvers();

  const timer = setTimeout(() => {
    reject(new Error(`Timeout waiting for event '${eventName}' after ${timeoutMs}ms`));
  }, timeoutMs);

  emitter.once(eventName, (data) => {
    clearTimeout(timer);
    resolve(data);
  });

  return promise;
}
```

---

## 3. High-Throughput Concurrency Limiter (Async Task Pool)

Firing 10,000 asynchronous database queries simultaneously using `Promise.all()` will instantly exhaust database connection pools and crash the backend with socket timeouts.

Use an **Async Concurrency Pool** to limit concurrent in-flight tasks to a fixed window (e.g. max 10 concurrent requests):

```javascript
// src/concurrency/async_pool.js

export async function asyncPool(concurrencyLimit, items, asyncIteratorFn) {
  const results = [];
  const executing = new Set();

  for (const item of items) {
    // 1. Wrap task in a Promise that removes itself from 'executing' upon completion:
    const taskPromise = Promise.resolve().then(() => asyncIteratorFn(item));
    results.push(taskPromise);

    executing.add(taskPromise);
    const cleanUp = () => executing.delete(taskPromise);
    taskPromise.then(cleanUp, cleanUp);

    // 2. If pool is full, wait for the fastest active task to complete:
    if (executing.size >= concurrencyLimit) {
      await Promise.race(executing);
    }
  }

  // 3. Wait for all remaining tasks to finish:
  return Promise.all(results);
}

// Execution Example:
const userIds = Array.from({ length: 1000 }, (_, i) => `user_${i}`);

// Processes 1,000 users with a strict concurrency ceiling of 10 at any given time:
const profiles = await asyncPool(10, userIds, async (id) => {
  console.log(`Fetching profile for ${id}...`);
  return await fetchUserProfileFromDatabase(id);
});

console.log(`Processed all ${profiles.length} user profiles safely.`);
```

---

## 4. Asynchronous Generators (`async*`) for Streaming Pagination

When querying massive datasets (e.g. scrolling through 1,000,000 database rows), loading everything into an in-memory array causes Out-Of-Memory crashes.

Use an **Async Generator (`async*`)** with **`yield`** to stream paginated results on-demand:

```javascript
// src/generators/paginated_cursor.js

export async function* fetchPaginatedRecords(apiEndpoint, pageSize = 100) {
  let nextCursor = null;
  let hasMore = true;

  while (hasMore) {
    const url = new URL(apiEndpoint);
    url.searchParams.set('limit', pageSize);
    if (nextCursor) {
      url.searchParams.set('cursor', nextCursor);
    }

    const response = await fetch(url.toString());
    const data = await response.json();

    // Yield records one by one:
    for (const record of data.items) {
      yield record;
    }

    nextCursor = data.nextCursor;
    hasMore = Boolean(nextCursor);
  }
}

// Consuming with 'for await...of':
async function processData() {
  const recordStream = fetchPaginatedRecords('https://api.internal/v1/audit-logs');

  for await (const record of recordStream) {
    // Consumes each record with constant memory consumption!
    console.log('Processing audit record:', record.id);
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Handle `unhandledRejection` Globally**
   In Node.js, unhandled promise rejections terminate the process with non-zero exit codes. Always register a global crash listener:
   ```javascript
   process.on('unhandledRejection', (reason, promise) => {
     console.error('Unhandled Promise Rejection at:', promise, 'reason:', reason);
   });
   ```

2. **`Promise.all` vs `Promise.allSettled` for Batch Operations**
   Use `Promise.all` when all operations are interdependent (all must succeed). Use `Promise.allSettled` when sending notifications or syncing batch records where one failure should not abort the rest of the batch.
