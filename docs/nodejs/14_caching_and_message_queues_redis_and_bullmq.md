# Module 14: Distributed Caching with Redis & Asynchronous Job Queues with BullMQ

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Distributed Systems, In-Memory Caching & Background Task Queues

---

## 1. Redis In-Memory Data Structures in Node.js (`ioredis`)

**Redis** is an ultra-low-latency in-memory data store used for caching, session stores, distributed locks, and message queues:

```bash
npm install ioredis bullmq
```

```javascript
// src/cache/redis_client.js
import Redis from 'ioredis';

export const redis = new Redis(process.env.REDIS_URL || 'redis://127.0.0.1:6379', {
  maxRetriesPerRequest: null, // Required for BullMQ workers!
  enableReadyCheck: false,
});

redis.on('connect', () => console.log('Connected to Redis Cluster'));
redis.on('error', (err) => console.error('[Redis Error]:', err));
```

---

## 2. The Cache-Aside Pattern with Thundering Herd (Stampede) Protection

The **Cache-Aside Pattern** checks Redis for cached data before querying the primary database.

### The Problem: Cache Stampede (Thundering Herd)

When a high-traffic cache key expires, 10,000 concurrent requests simultaneously miss the cache and hit the database at the exact same millisecond, crashing the database.

### Solution: Distributed Mutex Lock (Redlock pattern)

```javascript
// src/cache/cache_aside.js
import { redis } from './redis_client.js';

export async function getOrSetCache(key, ttlSeconds, fetchDbFn) {
  // 1. Check Redis Cache:
  const cached = await redis.get(key);
  if (cached) {
    return JSON.parse(cached);
  }

  // 2. Acquire Distributed Mutex Lock with 5-second lease:
  const lockKey = `lock:${key}`;
  const acquiredLock = await redis.set(lockKey, 'locked', 'EX', 5, 'NX');

  if (acquiredLock) {
    try {
      // 3. Fetch from primary database:
      const freshData = await fetchDbFn();

      // 4. Save to Redis with TTL expiration:
      await redis.set(key, JSON.stringify(freshData), 'EX', ttlSeconds);
      return freshData;
    } finally {
      // Release lock:
      await redis.del(lockKey);
    }
  } else {
    // 5. If another worker is already refreshing the cache, wait 100ms and re-check cache:
    await new Promise((resolve) => setTimeout(resolve, 100));
    return getOrSetCache(key, ttlSeconds, fetchDbFn);
  }
}
```

---

## 3. Background Message Queues with BullMQ

For asynchronous, long-running tasks (e.g. sending batch emails, generating PDF reports, video transcoding, webhook dispatching), executing tasks synchronously in an HTTP request blocks server throughput.

**BullMQ** is a Redis-backed job queue supporting retries, exponential backoffs, rate-limiting, and parent-child workflows:

```text
BullMQ Queue Pipeline:
[HTTP POST /checkout] ──► [BullMQ Producer: queue.add('processInvoice')] ──► Returns 202 Accepted (<5ms!)
                                      │
                                      ▼ (Redis Stream Queue)
                           [BullMQ Worker: Background Thread]

                           - Auto-Retries (3x Exponential Backoff)
                           - Dead-Letter Queue on Permanent Failure
```

---

## 4. BullMQ Producer & Worker Implementation

### 1. The Queue Producer (`src/queues/email_queue.js`)

```javascript
// src/queues/email_queue.js
import { Queue } from 'bullmq';
import { redis } from '../cache/redis_client.js';

export const emailQueue = new Queue('email-delivery', {
  connection: redis,
  defaultJobOptions: {
    attempts: 3, // Auto-retry up to 3 times
    backoff: {
      type: 'exponential',
      delay: 2000, // 2s, 4s, 8s backoff intervals
    },
    removeOnComplete: 100, // Keep last 100 completed jobs in Redis
    removeOnFail: 500,     // Keep failed jobs for debugging
  },
});

export async function dispatchWelcomeEmail(userId, email, name) {
  const job = await emailQueue.add('send-welcome', {
    userId,
    email,
    name,
    timestamp: new Date().toISOString(),
  });

  console.log(`[Queue]: Dispatched email job #${job.id} to BullMQ.`);
  return job.id;
}
```

---

### 2. The Background Worker (`src/workers/email_worker.js`)

```javascript
// src/workers/email_worker.js
import { Worker, QueueEvents } from 'bullmq';
import { redis } from '../cache/redis_client.js';

// Dedicated Worker processing jobs concurrently:
export const emailWorker = new Worker(
  'email-delivery',
  async (job) => {
    console.log(`[Worker]: Processing Job #${job.id} (${job.name}) for ${job.data.email}...`);

    // Simulate sending email via SES/SendGrid:
    if (job.data.email.endsWith('@error.com')) {
      throw new Error('Remote SMTP server rejected email recipient.');
    }

    await new Promise((r) => setTimeout(r, 1500));
    console.log(`[Worker]: Successfully sent email for Job #${job.id}!`);

    return { sentAt: new Date().toISOString() };
  },
  {
    connection: redis,
    concurrency: 10, // Process 10 background jobs simultaneously!
  }
);

// Worker Lifecycle Listeners:
emailWorker.on('failed', (job, err) => {
  console.error(`[Worker]: Job #${job?.id} failed on attempt ${job?.attemptsMade}:`, err.message);
});

emailWorker.on('completed', (job) => {
  console.log(`[Worker]: Job #${job.id} completed successfully.`);
});
```

---

## 5. Rate-Limiting with Redis Sliding Window

```javascript
// src/security/sliding_window_rate_limiter.js
import { redis } from '../cache/redis_client.js';

export async function checkRateLimit(ipAddress, limit = 60, windowSeconds = 60) {
  const key = `ratelimit:${ipAddress}`;
  const now = Date.now();
  const clearBefore = now - windowSeconds * 1000;

  // Atomic Redis Pipeline using Sorted Sets (ZSET):
  const multi = redis.multi();
  multi.zremrangebyscore(key, 0, clearBefore); // Remove timestamps older than window
  multi.zadd(key, now, `${now}-${Math.random()}`); // Add current request timestamp
  multi.zcard(key); // Count total requests in window
  multi.expire(key, windowSeconds);

  const results = await multi.exec();
  const requestCount = results[2][1]; // Extract zcard count

  return {
    allowed: requestCount <= limit,
    currentCount: requestCount,
    remaining: Math.max(0, limit - requestCount),
  };
}
```

---

## Troubleshooting & Best Practices

1. **Always Set `maxRetriesPerRequest: null` for BullMQ**
   BullMQ uses blocking Redis commands (`BRPOPLPUSH` / `BLMOVE`). If `maxRetriesPerRequest` is set to a finite number in `ioredis`, the worker will throw connection timeout exceptions on idle queues.

2. **Always Provide TTL on Cache Keys**
   Never execute `redis.set(key, val)` without an `EX <seconds>` expiration flag. Cache keys without TTL will accumulate indefinitely in RAM, eventually crashing Redis with an Out-Of-Memory error.
