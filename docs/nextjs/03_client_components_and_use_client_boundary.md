# Module 03: Client Components & The `'use client'` Boundary

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** Component Architecture & Hydration Boundaries

---

## 1. Demystifying the `'use client'` Directive

The `'use client'` directive is a special compiler instruction placed at the very top of a file (before any imports).

### Common Myth vs Reality:

- **Myth**: *"Adding `'use client'` means this component renders only in the browser and skips SSR."*
- **Reality**: `'use client'` defines the **boundary** where the module and all its imported dependencies must be packaged into the client JavaScript bundle. **Client Components are STILL pre-rendered to static HTML on the server** during initial page load for fast First Contentful Paint (FCP) and SEO, and then hydrated in the browser.

```
Module Dependency Boundary:
[Server Component: ProductPage.tsx] (Server-Only Module Graph)
        │
        ▼ (RSC Boundary crossed)
['use client' Directive: InteractiveRating.tsx] ◄── Added to Client Bundle Graph!
        │
        ├── imports StarIcon.tsx (Automatically bundled as Client Component)
        └── imports useAnimation.ts (Bundled into Client JS)
```

---

## 2. When to Use Client Components

Use Client Components **only** when your component requires:

1. **User Interactivity & Event Listeners**: `onClick`, `onChange`, `onScroll`, `onKeyDown`.
2. **React State & Lifecycle Hooks**: `useState`, `useReducer`, `useEffect`, `useLayoutEffect`, `useRef`.
3. **Browser Global APIs**: `localStorage`, `sessionStorage`, `navigator.geolocation`, `window.matchMedia`, WebSockets.
4. **React Context Consumers**: Calling `useContext(MyContext)` or `useTheme()`.
5. **Class Components or Third-Party Interactive Widgets** (e.g. Framer Motion, Leaflet maps).

---

## 3. The Leaf Component Pattern (Pushing the Boundary Down)

To minimize the size of the JavaScript bundle downloaded by mobile devices, **push the `'use client'` boundary down to the leaf nodes of your component tree**.

### ❌ Bad Architecture: Making the Entire Page a Client Component

```tsx
// src/app/products/[id]/page.tsx
"use client"; // ❌ BAD: Forces entire page, headers, footers, and database code into client bundle!

import { useState } from "react";

export default function ProductPage() {
  const [qty, setQty] = useState(1);
  // ...
}
```

### ✅ Good Architecture: Isolating the Interactive Island as a Leaf

```tsx
// src/components/QuantitySelector.tsx (Leaf Client Component)
"use client";

import { useState } from "react";

export function QuantitySelector({ onQuantityChange }: { onQuantityChange?: (q: number) => void }) {
  const [quantity, setQuantity] = useState(1);

  return (
    <div className="quantity-controls">
      <button onClick={() => setQuantity(Math.max(1, quantity - 1))}>-</button>
      <span>{quantity}</span>
      <button onClick={() => setQuantity(quantity + 1)}>+</button>
    </div>
  );
}
```

```tsx
// src/app/products/[id]/page.tsx (Server Component: Stays 100% on the server!)
import { db } from "@/lib/db";
import { notFound } from "next/navigation";
import { QuantitySelector } from "@/components/QuantitySelector";
import { AddToCartButton } from "@/components/AddToCartButton";

export default async function ProductPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const product = await db.product.findUnique({ where: { id } });

  if (!product) notFound();

  return (
    <div className="product-layout">
      {/* Static Server Content (0 KB JS): */}
      <h1>{product.title}</h1>
      <p>{product.description}</p>
      <span className="price">${product.price.toFixed(2)}</span>

      {/* Small Interactive Leaf Components: */}
      <QuantitySelector />
      <AddToCartButton productId={product.id} />
    </div>
  );
}
```

---

## 4. Passing Server Actions to Client Components

Client Components can invoke Server Actions passed as props or imported directly:

```tsx
// src/components/LikeButton.tsx (Client Component)
"use client";

import { useState, useTransition } from "react";

export function LikeButton({
  postId,
  initialLikes,
  onLikeAction, // Server Action passed as prop!
}: {
  postId: string;
  initialLikes: number;
  onLikeAction: (postId: string) => Promise<{ newLikes: number }>;
}) {
  const [likes, setLikes] = useState(initialLikes);
  const [isPending, startTransition] = useTransition();

  function handleClick() {
    startTransition(async () => {
      setLikes((l) => l + 1); // Optimistic increment
      const res = await onLikeAction(postId);
      setLikes(res.newLikes);
    });
  }

  return (
    <button onClick={handleClick} disabled={isPending} className="btn-like">
      ❤️ {likes} {isPending && "(syncing...)"}
    </button>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Hydration Mismatch with Browser-Only Values**
   If a Client Component reads `window.innerWidth` or `new Date().toLocaleTimeString()` during the initial render, the server HTML will differ from the client HTML, triggering a React Hydration Mismatch error.
   *Fix:* Initialize with static default state and update inside `useEffect()`:
   ```tsx
   const [mounted, setMounted] = useState(false);
   useEffect(() => setMounted(true), []);
   if (!mounted) return null; // Render browser-dependent UI only after hydration
   ```

2. **Passing Complex Class Instances across the Boundary**
   Props passed from Server Components to Client Components are serialized via JSON over the network. Class methods and prototypes are lost. Always pass plain objects and primitives.
