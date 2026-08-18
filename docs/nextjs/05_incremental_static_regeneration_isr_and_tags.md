# Module 05: Incremental Static Regeneration (ISR) & Cache Tags

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** Static Site Generation, On-Demand Cache Invalidation & Edge Purging

---

## 1. What Is Incremental Static Regeneration (ISR)?

Traditional web architectures forced a choice between two extremes:
1. **Static Site Generation (SSG)**: Blazing fast CDN delivery, but rebuilding 100,000 pages when a single typo is fixed takes 45 minutes of CI build time.
2. **Server-Side Rendering (SSR)**: Always fresh, but queries the database on every single hit, driving up database CPU costs and increasing server response latency.

**Incremental Static Regeneration (ISR)** combines the best of both worlds:
- Pages are generated as static HTML and cached on global Edge CDNs.
- Pages are revalidated in the background **without rebuilding the entire website**.
- Revalidation can occur on a **time schedule** (e.g. every 60 seconds) or **on-demand via webhooks/tags**.

```
Time-Based ISR Workflow:
1. User visits /products/keyboard ──► Edge CDN serves cached static HTML in 15ms.
2. (60 seconds elapse)
3. Next user visits /products/keyboard ──► Edge CDN serves stale cached HTML (instant 15ms).
   ├─► Background Worker: Re-renders page on server and updates Edge Cache!
4. Subsequent visitors receive the newly regenerated page instantly.
```

---

## 2. Time-Based Revalidation

### 1. Route-Level Time Revalidation

Set `revalidate` at the top of your `page.tsx`:

```tsx
// src/app/leaderboard/page.tsx

// Re-generate this page at most once every 300 seconds (5 minutes):
export const revalidate = 300;

export default async function LeaderboardPage() {
  const topPlayers = await fetchLeaderboardFromDatabase();

  return (
    <div>
      <h1>Global Tournament Leaderboard</h1>
      <p>Updated every 5 minutes</p>
      <ul>
        {topPlayers.map((player) => (
          <li key={player.id}>{player.name}: {player.score} pts</li>
        ))}
      </ul>
    </div>
  );
}
```

### 2. Fetch-Level Time Revalidation

```tsx
export default async function NewsFeed() {
  const res = await fetch("https://api.news.com/headlines", {
    next: { revalidate: 60 }, // Revalidate this specific fetch every 60 seconds
  });
  const news = await res.json();
  return <NewsList items={news} />;
}
```

---

## 3. On-Demand Revalidation with Cache Tags (`revalidateTag`)

Time-based revalidation is insufficient when data changes unpredictably (e.g. an e-commerce price drop or a headless CMS publish event). 

**Cache Tags** allow grouping related data across multiple routes and **purging the cache instantly on-demand**:

```tsx
// src/app/products/[id]/page.tsx
export default async function ProductDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  // Tag this fetch with 'product-detail' and the specific product ID:
  const res = await fetch(`https://api.example.com/products/${id}`, {
    next: {
      tags: ["products", `product-${id}`],
    },
  });

  const product = await res.json();
  return <ProductView product={product} />;
}
```

### Triggering Cache Invalidation in a Server Action or Webhook:

```typescript
// src/app/actions/productActions.ts
"use server";

import { revalidateTag, revalidatePath } from "next/cache";

export async function updateProductPrice(productId: string, newPrice: number) {
  await db.product.update({
    where: { id: productId },
    data: { price: newPrice },
  });

  // 1. Invalidate all pages tagged with this specific product:
  revalidateTag(`product-${productId}`);

  // 2. Invalidate the global products category list:
  revalidateTag("products");

  // 3. Or invalidate a specific route path:
  revalidatePath(`/products/${productId}`);
}
```

---

## 4. `generateStaticParams()` (Pre-rendering Dynamic Routes)

To pre-render dynamic routes (`/products/[id]`) at build time rather than on the first request:

```tsx
// src/app/products/[id]/page.tsx
import { db } from "@/lib/db";

// Pre-render the top 50 most popular products at build time:
export async function generateStaticParams() {
  const popularProducts = await db.product.findMany({
    select: { id: true },
    take: 50,
  });

  return popularProducts.map((p) => ({
    id: p.id,
  }));
}

export default async function ProductPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const product = await db.product.findUnique({ where: { id } });
  return <div>{product?.title}</div>;
}
```

---

## 5. Headless CMS Revalidation Webhook Handler

```typescript
// src/app/api/revalidate/route.ts
import { type NextRequest, NextResponse } from "next/server";
import { revalidateTag } from "next/cache";

export async function POST(request: NextRequest) {
  const secret = request.nextUrl.searchParams.get("secret");

  // Validate shared secret token from CMS (Contentful / Sanity / Strapi)
  if (secret !== process.env.CMS_REVALIDATE_SECRET) {
    return NextResponse.json({ error: "Invalid secret token" }, { status: 401 });
  }

  const body = await request.json();
  const tagToPurge = body.tag || "content";

  // Purge the cache immediately across all global Edge CDNs:
  revalidateTag(tagToPurge);

  return NextResponse.json({
    revalidated: true,
    tag: tagToPurge,
    timestamp: Date.now(),
  });
}
```

---

## Troubleshooting & Best Practices

1. **`dynamicParams` Configuration**
   When using `generateStaticParams()`, control what happens when a user requests a path that was **not** pre-rendered at build time:
   ```typescript
   export const dynamicParams = true;  // Default: Generates the page on-demand on first visit
   export const dynamicParams = false; // Returns a 404 for any path not in generateStaticParams
   ```
