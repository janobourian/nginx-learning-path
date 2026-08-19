# Module 04: Data Fetching, Next.js Data Cache & Request Memoization

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Server Data Pipelines, Caching & Performance

---

## 1. The Extended `fetch()` API in Next.js

Next.js patches the native Web `fetch()` API on the server to introduce **caching options, request memoization, and on-demand revalidation flags**.

```typescript
fetch(url, {
  cache: "force-cache" | "no-store",
  next: {
    revalidate: false | 0 | number, // Time-based revalidation in seconds
    tags: string[],                 // Cache tag identifiers for on-demand purging
  },
});
```

### Data Fetching Modes

| Fetch Option | Behavior | Primary Use Case |
| :--- | :--- | :--- |
| **`{ cache: 'force-cache' }`** (Default) | Cached indefinitely in Next.js Data Cache | Static blog posts, marketing content, product catalogs |
| **`{ next: { revalidate: 3600 } }`** | **ISR (Time-Based)**: Re-fetches at most once every hour | Leaderboards, weather feeds, e-commerce pricing |
| **`{ cache: 'no-store' }`** (or `revalidate: 0`) | **Dynamic SSR**: Fetches fresh data on **every single request** | Real-time dashboards, user bank balances, live notifications |

---

## 2. Request Memoization (Per-Request Deduplication)

Consider a scenario where multiple components in a single render pass need user profile data:

- `app/layout.tsx` calls `getUserProfile(id)` to render the header avatar.
- `app/dashboard/page.tsx` calls `getUserProfile(id)` to render the welcome message.
- `app/components/Sidebar.tsx` calls `getUserProfile(id)` to render user permissions.

In vanilla Node.js, this would execute 3 duplicate HTTP requests to your backend database.

In Next.js, **Request Memoization** automatically intercepts identical `GET` fetch requests during a single render pass and **executes the network call exactly ONCE**, returning the memoized result to all subsequent callers!

```text
Request Memoization Pipeline (Single Server Request):
[Layout: fetch('/api/user/1')] ──► (Network Call Executed) ──► Stored in Memory Cache
[Page:   fetch('/api/user/1')] ──► (Cache Hit! Zero Network Call)
[Sidebar:fetch('/api/user/1')] ──► (Cache Hit! Zero Network Call)
```

*Note: Request Memoization is scoped strictly to the lifecycle of a single incoming server request. Once the request finishes, the memory cache is destroyed.*

---

## 3. Memoizing Non-Fetch Database Calls (`React.cache()`)

If you fetch data via an ORM (Prisma, Drizzle, Mongoose) rather than `fetch()`, native `fetch` memoization does not apply.

Use React's **`cache()`** utility to wrap ORM queries with the exact same per-request deduplication:

```typescript
// src/lib/getUser.ts
import { cache } from "react";
import { db } from "@/lib/db";

// 'cache()' ensures that calling getUser('u_123') 5 times in one page render
// queries the database only ONCE!
export const getUser = cache(async (userId: string) => {
  console.log(`[DB Query]: Executing SQL select for user ${userId}`);
  return await db.user.findUnique({
    where: { id: userId },
    select: { id: true, name: true, email: true, role: true },
  });
});
```

---

## 4. Parallel vs Sequential Data Fetching (Preventing Waterfalls)

When a page requires data from multiple independent sources, fetching sequentially doubles page latency:

### ❌ Bad: Sequential Fetching (Waterfall)

```tsx
export default async function SlowDashboard() {
  // Total wait time: 200ms + 300ms = 500ms!
  const user = await fetchUser();       // Takes 200ms
  const projects = await fetchProjects(); // Takes 300ms (Waits for user to finish first!)

  return <div>...</div>;
}
```

### ✅ Good: Parallel Fetching with `Promise.all`

```tsx
export default async function FastDashboard() {
  // Total wait time: max(200ms, 300ms) = 300ms! (Both run simultaneously)
  const [user, projects] = await Promise.all([
    fetchUser(),
    fetchProjects(),
  ]);

  return <div>...</div>;
}
```

---

## 5. Streaming Data with `<Suspense>` & `loading.tsx`

If one data source is fast (20ms) and another is slow (1,500ms), do not block the entire page. Use **`<Suspense>`** to stream the fast content immediately and display a loading skeleton for the slow section:

```tsx
// src/app/dashboard/page.tsx
import { Suspense } from "react";
import { QuickMetrics } from "@/components/QuickMetrics";
import { HeavyAnalyticsChart } from "@/components/HeavyAnalyticsChart";

export default async function DashboardPage() {
  return (
    <div className="space-y-6">
      <h1>Executive Dashboard</h1>

      {/* Renders immediately (fast database query) */}
      <QuickMetrics />

      {/* Suspended boundary: Streams in when the 2-second heavy query completes */}
      <Suspense fallback={<div className="h-64 bg-slate-900 animate-pulse rounded-lg" />}>
        <HeavyAnalyticsChart />
      </Suspense>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Opting Out of Caching Globally for a Route**
   If an entire route must always be dynamic (e.g. real-time telemetry):

   ```typescript
   // At the top of page.tsx:
   export const dynamic = "force-dynamic";
   export const revalidate = 0;
   ```

2. **Using Cookies or Headers Forces Dynamic Rendering**
   Calling `cookies()` or `headers()` inside a Server Component automatically switches the route from static caching to **Dynamic Rendering** on every request.
