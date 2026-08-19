# Module 14: Distributed Caching & Cache Stampede Defense (XFetch, Bloom Filters & Redlock)

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Distributed Caching, Cache Stampede & Distributed Mutexes

---

## 1. The 3 Cache Catastrophes (And Architectural Defenses)

```text
┌─────────────────────────────────────────────────────────────┐
│                 The 3 Cache Breakdown Catastrophes          │
├────────────────────┬────────────────────────────────────────┤
│ **1. Cache**       │ High-traffic key expires; thousands of │
│    **Stampede**    │ requests hit DB at the same millisecond│
│    **(Thundering)**│ ──► **Defense: XFetch (Probabilistic)**│
├────────────────────┼────────────────────────────────────────┤
│ **2. Cache**       │ Thousands of keys expire simultaneously│
│    **Avalanche**   │ at midnight, crashing DB.              │
│                    │ ──► **Defense: Randomized TTL Jitter** │
├────────────────────┼────────────────────────────────────────┤
│ **3. Cache**       │ Attackers query non-existent IDs       │
│    **Penetration** │ repeatedly, bypassing cache completely.│
│                    │ ──► **Defense: Bloom Filters**         │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Preventing Cache Avalanche with Randomized TTL Jitter

When seeding cache keys, never set a static TTL (e.g. `TTL = 3600`). If 100,000 keys are generated at 10:00 AM, all 100,000 will expire at 11:00 AM simultaneously, crushing the database.

**Add Randomized Jitter to Every Cache Key**:

```javascript
export function calculateJitteredTtl(baseTtlSeconds = 3600, jitterPercent = 0.2) {
  const maxJitter = baseTtlSeconds * jitterPercent;
  const randomJitter = (Math.random() * 2 - 1) * maxJitter; // +/- 20%
  return Math.floor(baseTtlSeconds + randomJitter);
}
```

---

## 3. The XFetch Algorithm (Probabilistic Early Expiration)

The **XFetch Algorithm** (published by Vattani et al.) uses probabilistic modeling to recompute and refresh a cache key **in the background slightly BEFORE it expires**, with higher probability as the expiration draws near and request load increases:

```javascript
// src/cache/xfetch.js
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);

/**

 * XFetch Probabilistic Cache Refresh:
 * Formula: delta * beta * ln(rand()) <= (now - expiry)
 */
export async function xfetch(key, ttlSeconds, computeFn, beta = 1.0) {
  const raw = await redis.get(key);

  if (raw) {
    const { value, deltaMs, expiryTime } = JSON.parse(raw);
    const now = Date.now();

    // Probabilistic early expiration check:
    const timeRemainingMs = expiryTime - now;
    const shouldRefreshEarly = -deltaMs * beta * Math.log(Math.random()) >= timeRemainingMs;

    if (!shouldRefreshEarly) {
      return value; // Return cached value immediately!
    }

    console.log(`[XFetch]: Probabilistic early refresh triggered for key '${key}'`);
  }

  // Compute fresh value from database:
  const startTime = Date.now();
  const freshValue = await computeFn();
  const deltaMs = Date.now() - startTime;
  const expiryTime = Date.now() + ttlSeconds * 1000;

  const payload = JSON.stringify({ value: freshValue, deltaMs, expiryTime });
  await redis.set(key, payload, 'EX', ttlSeconds);

  return freshValue;
}
```

---

## 4. Distributed Locking with the Redlock Algorithm

When updating shared inventory across multiple microservice pods, local in-memory locks fail.

Use the **Redlock Algorithm** to acquire a distributed mutex with automatic lease expirations:

```javascript
// src/concurrency/redlock.js
import crypto from 'node:crypto';
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);

export class DistributedLock {
  static async acquire(resourceKey, ttlMs = 5000) {
    const lockValue = crypto.randomUUID(); // Unique secret token to verify owner!
    const key = `lock:${resourceKey}`;

    // 'NX' = Only set if Not Exists; 'PX' = Expire in milliseconds:
    const acquired = await redis.set(key, lockValue, 'PX', ttlMs, 'NX');

    if (!acquired) {
      throw new Error(`Could not acquire lock for ${resourceKey}: Resource is busy.`);
    }

    return {
      release: async () => {
        // Lua script ensures atomic check-and-delete (Only delete if token matches!):
        const luaScript = `
          if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
          else
            return 0
          end
        `;
        await redis.eval(luaScript, 1, key, lockValue);
      },
    };
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Use Lua Scripts for Lock Releases**
   Never execute `if (get(lock) === myToken) del(lock)` in two separate commands. If the lock expires between the `get` and the `del`, you will delete another client's newly acquired lock! Always use atomic Lua scripts.

2. **Cache Null Values for Non-Existent Keys**
   To defeat **Cache Penetration** attacks where attackers request non-existent IDs, cache `{ notFound: true }` in Redis with a short 60-second TTL to protect the database.
