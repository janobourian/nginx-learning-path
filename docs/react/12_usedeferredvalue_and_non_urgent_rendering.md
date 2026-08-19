# Module 12: `useDeferredValue` & Adaptive Non-Urgent Rendering

**Track:** React — Modern UI & Fiber Architecture
**Category:** Concurrent Scheduling, Adaptive Latency & Rendering Optimization

---

## 1. What Is `useDeferredValue`?

**`useDeferredValue`** is a built-in React hook that accepts a value and returns a **deferred copy** of that value that "lags behind" during high-priority main-thread work.

```typescript
const deferredValue = useDeferredValue(value);
```

When a user interacts with the application (e.g. typing rapidly into a search bar), React prioritizes keeping the input responsive. The `deferredValue` retains its previous value until the browser has finished painting urgent updates, at which point React re-renders the background components with the updated deferred value.

---

## 2. `useDeferredValue` vs Debouncing vs Throttling

For years, developers used `lodash.debounce` or `lodash.throttle` to manage expensive search and filtering tasks. However, timer-based throttling has severe drawbacks compared to React's concurrent `useDeferredValue`:

| Feature / Metric | Debouncing (`setTimeout`) | Throttling | `useDeferredValue` (Concurrent React) |
| :--- | :--- | :--- | :--- |
| **Delay Mechanism** | Fixed arbitrary timer (e.g. 300ms) | Fixed interval rate | **Adaptive to hardware CPU speed** |
| **Fast Devices (M3/i9)** | Unnecessary 300ms artificial delay | Delayed | **Instant execution (<5ms)** |
| **Slow Devices (Mobile)** | Still freezes if calculation > 300ms | Freezes | **Gracefully yields and never freezes UI** |
| **Cancelability** | Manual timer clearing | Manual | **Automatic work-in-progress abandonment** |
| **Frame Rate Impact** | Can cause stutter | Can cause stutter | **Guarantees 60fps responsiveness** |

---

## 3. How `useDeferredValue` Works Under the Hood

When `value` changes from `"A"` to `"AB"`:

1. **First Render (Urgent)**: React renders the component with `query = "AB"`, but `deferredQuery = "A"`. The input updates on screen instantly.
2. **Second Render (Non-Urgent Background)**: React immediately kicks off a background transition render in memory with `deferredQuery = "AB"`.
3. **If user types "ABC" during step 2**: React **aborts** the background render for "AB" and immediately starts rendering "ABC".

```text
User Action: Types 'AB'
    │
    ▼
[Render 1: Urgent] ──► query = 'AB', deferredQuery = 'A' (Stale) ──► Screen paints input instantly
    │
    ▼ (Main thread idle)
[Render 2: Deferred] ─► query = 'AB', deferredQuery = 'AB' (Fresh) ──► Screen updates heavy list
```

---

## 4. Production Example: Real-Time Complex Data Grid Filtering

Let's build a searchable data table containing 20,000 records without visual stutter:

```tsx
import React, { useState, useDeferredValue, useMemo } from "react";

export interface DataRow {
  id: string;
  sku: string;
  name: string;
  category: string;
  inStock: boolean;
  unitPrice: number;
}

// Heavy Presentational Grid Component (Wrapped in React.memo!)
export const HeavyDataGrid = React.memo(function HeavyDataGrid({
  filterQuery,
  records,
}: {
  filterQuery: string;
  records: DataRow[];
}) {
  console.log(`[HeavyDataGrid] Filtering & rendering ${records.length} records for: "${filterQuery}"`);

  const filtered = useMemo(() => {
    if (!filterQuery.trim()) return records;
    const q = filterQuery.toLowerCase();
    return records.filter(
      (r) =>
        r.name.toLowerCase().includes(q) ||
        r.sku.toLowerCase().includes(q) ||
        r.category.toLowerCase().includes(q)
    );
  }, [records, filterQuery]);

  return (
    <div className="grid-table">
      <div className="grid-summary">Showing {filtered.length} matching records</div>
      <div className="grid-rows">
        {filtered.slice(0, 100).map((row) => (
          <div key={row.id} className="grid-row">
            <span className="sku">{row.sku}</span>
            <span className="name">{row.name}</span>
            <span className="category">{row.category}</span>
            <span className="price">${row.unitPrice.toFixed(2)}</span>
          </div>
        ))}
      </div>
    </div>
  );
});

// Parent Controller Component
export function InventoryDashboard({ allRecords }: { allRecords: DataRow[] }) {
  const [search, setSearch] = useState("");

  // Defer the search query for the heavy grid:
  const deferredSearch = useDeferredValue(search);

  // Detect whether the current UI state is stale:
  const isStale = search !== deferredSearch;

  return (
    <div className="inventory-view">
      <header className="search-bar">
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search 20,000 SKUs..."
          className="search-input"
        />
        {isStale && <span className="status-indicator">Updating list...</span>}
      </header>

      {/* Dim the grid slightly when displaying stale background data */}
      <div
        className="grid-wrapper"
        style={{
          opacity: isStale ? 0.6 : 1,
          transition: "opacity 0.15s ease",
        }}
      >
        <HeavyDataGrid filterQuery={deferredSearch} records={allRecords} />
      </div>
    </div>
  );
}
```

---

## 5. `useDeferredValue` with `initialValue` (React 19)

In React 19, `useDeferredValue` accepts an optional second argument `initialValue`:

```typescript
const deferredValue = useDeferredValue(value, initialValue);
```

During the very first mount of the component, `deferredValue` returns `initialValue`, and immediately schedules a background transition to render `value`. This allows rendering a lightweight placeholder on initial page load before hydrating the full complex graph.

---

## Troubleshooting & Best Practices

1. **Child Component Must Be Memoized (`React.memo`)**
   For `useDeferredValue` to actually skip rendering during the urgent phase, the child component receiving the deferred value **must be wrapped in `React.memo`**. If the child is not memoized, it will re-render anyway during the urgent phase when the parent re-renders.

2. **Do Not Mix `useTransition` and `useDeferredValue` for the Same State**
   Choose one:

   - Use **`useTransition`** when you have direct access to the `setState` function.
   - Use **`useDeferredValue`** when you receive the value as a prop or from a third-party hook.
