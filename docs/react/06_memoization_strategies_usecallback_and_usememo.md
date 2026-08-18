# Module 06: Memoization Strategies — `useMemo`, `useCallback` & `React.memo`

**Track:** React — Modern UI & Fiber Architecture  
**Category:** Performance Optimization & Reference Stability

---

## 1. Why Do Components Re-Render in React?

By default in React:
> **When a parent component re-renders, ALL of its child components recursively re-render**, regardless of whether their props have changed!

For lightweight UI trees, this default behavior is fast and unnoticeable. However, for large component trees (e.g. data tables with 5,000 cells, interactive charts, complex forms), unnecessary child re-renders create noticeable frame drops and CPU spikes.

---

## 2. Component Memoization with `React.memo`

`React.memo` is a Higher-Order Component (HOC) that wraps a component and **skips re-rendering if its props have not changed (shallow equality check)**:

```tsx
import React from "react";

export interface HeavyChartProps {
  dataPoints: number[];
  title: string;
  onPointClick: (point: number) => void;
}

export const HeavyChart = React.memo(function HeavyChart({
  dataPoints,
  title,
  onPointClick,
}: HeavyChartProps) {
  console.log(`[HeavyChart] Rendering expensive chart: ${title}`);
  return (
    <div className="chart">
      <h3>{title}</h3>
      {/* Heavy SVG / Canvas rendering here */}
    </div>
  );
});
```

### The Referential Equality Problem: Why `React.memo` Breaks

In JavaScript, objects, arrays, and functions are compared by **reference identity**, not structural value:

```typescript
{} === {}       // false (different memory references)
[] === []       // false
(() => {}) === (() => {}) // false
```

If a parent component passes an inline object or inline function to a `React.memo` child:

```tsx
// ❌ FAILS TO MEMOIZE: Every render creates a NEW function and object reference!
<HeavyChart
  title="Analytics"
  dataPoints={data}
  onPointClick={(point) => console.log(point)} // NEW reference on every render!
/>
```

Because `prevProps.onPointClick !== nextProps.onPointClick`, `React.memo` fails and the child re-renders anyway!

---

## 3. Preserving Function References with `useCallback`

`useCallback` caches a function definition between renders, returning the **exact same memory reference** until its dependencies change:

```tsx
import { useState, useCallback } from "react";
import { HeavyChart } from "./HeavyChart";

export function Dashboard() {
  const [query, setQuery] = useState("");
  const [data] = useState<number[]>([10, 25, 40, 85]);

  // ✅ STABLE FUNCTION REFERENCE: Memory reference preserved across renders
  const handlePointClick = useCallback((point: number) => {
    console.log("Point clicked:", point);
  }, []); // Dependencies: empty array = never re-creates

  return (
    <div>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
      {/* Typing in <input> re-renders Dashboard, but HeavyChart is SKIPPED! */}
      <HeavyChart
        title="Performance Metrics"
        dataPoints={data}
        onPointClick={handlePointClick}
      />
    </div>
  );
}
```

---

## 4. Caching Expensive Computations with `useMemo`

`useMemo` caches the **result of a calculation** between renders:

```tsx
const cachedValue = useMemo(() => calculateExpensiveValue(a, b), [a, b]);
```

### 1. Heavy Mathematical / Filtering Calculations

```tsx
import { useState, useMemo } from "react";

export function ProductCatalog({ products }: { products: Product[] }) {
  const [search, setSearch] = useState("");
  const [minRating, setMinRating] = useState(4);

  // Filter 50,000 items only when products, search, or minRating changes:
  const filteredProducts = useMemo(() => {
    console.log("Filtering products list...");
    const query = search.toLowerCase();
    return products.filter(
      (p) => p.title.toLowerCase().includes(query) && p.rating >= minRating
    );
  }, [products, search, minRating]);

  return (
    <div>
      <input value={search} onChange={(e) => setSearch(e.target.value)} />
      <ProductList items={filteredProducts} />
    </div>
  );
}
```

### 2. Preserving Object Reference Stability for Context or Hooks

```tsx
// Stabilizing an object passed into Context.Provider to prevent cascading re-renders:
const authContextValue = useMemo(() => ({
  user,
  token,
  isAuthenticated: Boolean(user),
}), [user, token]);

return (
  <AuthContext.Provider value={authContextValue}>
    {children}
  </AuthContext.Provider>
);
```

---

## 5. Relationship Between `useCallback` and `useMemo`

`useCallback` is simply syntactic sugar over `useMemo` when returning a function:

```typescript
// These two declarations are 100% equivalent in React:
const fn1 = useCallback((x: number) => x * 2, [deps]);
const fn2 = useMemo(() => (x: number) => x * 2, [deps]);
```

---

## 6. When NOT to Memoize (Over-Optimization Costs)

Memoization is not free:
1. It consumes memory to store cached values and dependency arrays in the Fiber node.
2. On every render, React must loop through the dependency array and perform `Object.is()` comparisons.

### Don't Memoize When:
- The calculation is cheap (e.g. `items.length`, `a + b`, simple string formatting).
- The child component receiving the prop is **not** wrapped in `React.memo`. (If the child re-renders anyway, stabilizing prop references accomplishes nothing).

---

## Troubleshooting & Best Practices

1. **Stale Closures inside `useCallback`**
   If you reference a state variable inside `useCallback` but forget to list it in the dependency array:
   ```tsx
   // ❌ STALE CLOSURE: count is permanently locked to 0!
   const increment = useCallback(() => {
     setCount(count + 1);
   }, []); // Missing 'count' in deps!

   // ✅ CORRECT: Use functional update to avoid needing 'count' in deps:
   const increment = useCallback(() => {
     setCount((prev) => prev + 1);
   }, []); // Safe and stable!
   ```