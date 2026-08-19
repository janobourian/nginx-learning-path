# Module 11: Next.js Caching Architecture — 4-Tier Hierarchy Deep Dive

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Caching Architecture, Memory Invalidation & Performance Tuning

---

## 1. The 4-Tier Next.js Caching Hierarchy

Next.js App Router employs an advanced **4-Tier Caching System** that coordinates caching across the server memory, persistent disk storage, Edge CDNs, and the client browser:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    The 4-Tier Next.js Caching Pyramid                   │
│                                                                         │
│  [1. Router Cache] ─────────► Client Browser In-Memory (Per Session)    │
│                                                                         │
│  [2. Full Route Cache] ─────► Server / CDN (Static HTML & RSC Payloads) │
│                                                                         │
│  [3. Data Cache] ───────────► Server Persistent Disk (Across Requests)  │
│                                                                         │
│  [4. Request Memoization] ──► Server Memory (Single Render Pass)        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Deep Dive: The 4 Caching Tiers

| Cache Tier | Where It Lives | What It Stores | Purpose / Duration | How to Invalidate / Purge |
| :--- | :--- | :--- | :--- | :--- |
| **1. Request Memoization** | Server RAM | Return values of identical `fetch(GET)` calls | Deduplicates duplicate calls within **1 render pass** | Automatic (Destroyed when server request completes) |
| **2. Data Cache** | Server Disk / Storage | Output of `fetch()` requests with `{ cache: 'force-cache' }` | Persists data **across user requests and deployments** | `revalidateTag(tag)`, `revalidatePath(path)`, time revalidate |
| **3. Full Route Cache** | Server / CDN | Compiled HTML and RSC Flight Payloads | Serves pre-rendered static routes instantly | `revalidatePath()`, redeployment |
| **4. Router Cache** | Browser RAM | RSC Flight Payloads of visited routes | Instant back/forward navigation without network hits | `router.refresh()`, Server Actions |

---

## 3. Tier 1: Request Memoization (Server RAM)

When multiple components independently call the exact same fetch URL with the same parameters during a single server render, Next.js memoizes the request:

```typescript
// Component A (app/layout.tsx):
await fetch('https://api.example.com/user/me'); // ──► Executes real HTTP request

// Component B (app/dashboard/page.tsx):
await fetch('https://api.example.com/user/me'); // ──► Reads from Request Memoization RAM!
```

---

## 4. Tier 2: The Data Cache (Persistent Across Requests)

Unlike Request Memoization (which vanishes after the request ends), the **Data Cache** writes responses to disk and keeps them available for all future users:

```typescript
// Cached indefinitely across all server requests:
fetch('https://api.example.com/products', {
  cache: 'force-cache',
  next: { tags: ['products'] },
});

// Invalidate on-demand in any Server Action:
import { revalidateTag } from 'next/cache';
revalidateTag('products');
```

---

## 5. Tier 3: Full Route Cache (Static SSG / ISR)

At build time (`next build`), Next.js identifies routes that do not rely on dynamic request-time data (no cookies, no headers, no un-cached fetches) and pre-renders their HTML and RSC payloads into the **Full Route Cache**.

### What Makes a Route Dynamic (Opting Out of Full Route Cache)

A route automatically switches from **Static (Cached)** to **Dynamic (Rendered per-request)** if any of the following occur:

1. Calling `cookies()` from `next/headers`.
2. Calling `headers()` from `next/headers`.
3. Reading `searchParams` in a `page.tsx`.
4. Using `fetch(url, { cache: 'no-store' })`.
5. Declaring `export const dynamic = 'force-dynamic'`.
6. Calling `unstable_noStore()` inside a component.

---

## 6. Tier 4: Client-Side Router Cache (Browser Session RAM)

As the user navigates between routes, Next.js stores the RSC payloads of visited pages in the browser's in-memory **Router Cache**.

- **Prefetched Static Routes**: Cached for 5 minutes.
- **Dynamic Routes**: Cached for 30 seconds.
- When the user clicks the browser "Back" button, the page restores **instantly from client memory with 0ms network latency**.

### Purging the Client Router Cache

```tsx
"use client";

import { useRouter } from "next/navigation";

export function RefreshButton() {
  const router = useRouter();

  function handleHardRefresh() {
    // Purges client router cache and fetches fresh data from server:
    router.refresh();
  }

  return <button onClick={handleHardRefresh}>Refresh Feed</button>;
}
```

---

## 7. Next.js Caching Control Matrix

```typescript
// src/app/dashboard/page.tsx

// 1. Force the entire route to always be dynamic (No Full Route Cache)
export const dynamic = "force-dynamic";

// 2. Disable fetch caching for this entire route segment
export const fetchCache = "force-no-store";

// 3. Time-based revalidation (Seconds)
export const revalidate = 0; // 0 = dynamic, >0 = ISR
```

---

## Troubleshooting & Best Practices

1. **Stale Data After Database Mutation**
   If you update a database record via a Server Action or Route Handler but the page still displays old data, you forgot to trigger revalidation. Call `revalidatePath('/my-route')` or `revalidateTag('my-tag')` immediately following the database write.

2. **Debugging Cache Hits via Response Headers**
   In production, Next.js attaches the `x-nextjs-cache` header to responses:

   - `HIT`: Served from Data Cache / Full Route Cache.
   - `MISS`: First request fetched from origin and populated into cache.
   - `STALE`: Served stale cache while background ISR regeneration occurs.
   - `REVALIDATED`: Cache was successfully updated.
