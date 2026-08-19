# Module 04: Side Effects, the `useEffect` Lifecycle & Synchronization

**Track:** React — Modern UI & Fiber Architecture
**Category:** Side Effects, Browser Synchronization & Cleanup Lifecycle

---

## 1. What Is a Side Effect in React?

A **Side Effect** is any operation that interacts with the world outside the local React rendering boundary:

- Making asynchronous HTTP requests (`fetch`, Axios).
- Setting up event listeners on `window` or `document`.
- Starting and stopping timers (`setInterval`, `setTimeout`).
- Subscribing to WebSockets or message brokers.
- Synchronizing with non-React third-party libraries (Chart.js, Leaflet, D3).

In React, rendering must be kept pure. Side effects are declared using the **`useEffect`** hook to synchronize your component with an external system.

---

## 2. `useEffect` Execution Timing

Unlike render logic (which executes synchronously before DOM updates), `useEffect` runs **asynchronously after the browser has committed the DOM and painted the screen**. This ensures that heavy side-effect work does not block user interactions or frame animations.

```text
React Component Execution Lifecycle:
1. Render Phase ──────► Component function executes, JSX / Virtual DOM evaluated
2. Commit Phase ──────► React updates real DOM nodes to match Virtual DOM
3. Paint Phase  ──────► Browser paints updated pixels onto user screen
4. Effect Phase ──────► React executes all queued `useEffect` callbacks asynchronously!
```

---

## 3. The Dependency Array (`deps`)

The second argument to `useEffect` controls when the effect executes:

```tsx
// 1. No Dependency Array: Runs on INITIAL MOUNT + AFTER EVERY SINGLE RE-RENDER
useEffect(() => {
  console.log("Runs after every render (rarely recommended)");
});

// 2. Empty Dependency Array []: Runs ONLY ONCE when component MOUNTS
useEffect(() => {
  console.log("Runs once on mount");
}, []);

// 3. Array with Dependencies [a, b]: Runs on MOUNT + whenever 'a' OR 'b' changes
useEffect(() => {
  console.log(`Runs when userId (${userId}) or page (${page}) changes`);
}, [userId, page]);
```

---

## 4. The Cleanup Function & Preventing Memory Leaks

If your effect sets up an ongoing resource (event listener, timer, WebSocket), it **must return a cleanup function**.

React runs the cleanup function:

1. **Before executing the effect again** (when dependencies change).
2. **When the component unmounts** from the DOM.

```tsx
import { useState, useEffect } from "react";

export function WindowResizeMonitor() {
  const [windowWidth, setWindowWidth] = useState<number>(() =>
    typeof window !== "undefined" ? window.innerWidth : 0
  );

  useEffect(() => {
    const handleResize = () => {
      setWindowWidth(window.innerWidth);
    };

    // 1. Setup subscription
    window.addEventListener("resize", handleResize);

    // 2. Return cleanup function (MANDATORY to prevent memory leaks!)
    return () => {
      window.removeEventListener("resize", handleResize);
    };
  }, []); // Empty deps: setup on mount, cleanup on unmount

  return <p>Current Window Width: {windowWidth}px</p>;
}
```

---

## 5. Handling Race Conditions in Data Fetching with `AbortController`

A common bug in asynchronous data fetching occurs when a user rapidly changes parameters (e.g. searching for "A", then "AB", then "ABC"). Because network requests finish in non-deterministic order, the older request for "A" might resolve *after* "ABC", overwriting the newer results.

Use **`AbortController`** inside `useEffect` to cancel in-flight requests when dependencies change:

```tsx
import { useState, useEffect } from "react";

interface SearchResult {
  id: string;
  title: string;
}

export function AutoCompleteSearch({ query }: { query: string }) {
  const [results, setResults] = useState<SearchResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!query.trim()) {
      setResults([]);
      return;
    }

    const controller = new AbortController();
    setIsLoading(true);
    setError(null);

    async function executeSearch() {
      try {
        const res = await fetch(`/api/search?q=${encodeURIComponent(query)}`, {
          signal: controller.signal, // Connect abort signal
        });

        if (!res.ok) throw new Error("Search query failed");
        const data = await res.json();
        setResults(data);
      } catch (err: unknown) {
        if ((err as Error).name === "AbortError") {
          // Request was deliberately canceled; ignore error
          return;
        }
        setError((err as Error).message);
      } finally {
        setIsLoading(false);
      }
    }

    executeSearch();

    // Cleanup: Abort the previous network request if query changes before response arrives!
    return () => {
      controller.abort();
    };
  }, [query]);

  return (
    <div>
      {isLoading && <p>Searching...</p>}
      {error && <p className="error">{error}</p>}
      <ul>
        {results.map((item) => (
          <li key={item.id}>{item.title}</li>
        ))}
      </ul>
    </div>
  );
}
```

---

## 6. When NOT to Use `useEffect` (The Modern React Guidelines)

In older React codebases, developers overused `useEffect` for things that should not be effects.

### 1. Do NOT use `useEffect` to transform data for rendering

```tsx
// ❌ WRONG: Unnecessary state and effect causing extra render cycle
const [items, setItems] = useState([]);
const [filteredItems, setFilteredItems] = useState([]);
useEffect(() => {
  setFilteredItems(items.filter((i) => i.active));
}, [items]);

// ✅ CORRECT: Calculate directly during render (or use useMemo)
const filteredItems = items.filter((i) => i.active);
```

### 2. Do NOT use `useEffect` to handle user event reactions

```tsx
// ❌ WRONG: Triggering side effect via state watch
const [isSubmitted, setIsSubmitted] = useState(false);
useEffect(() => {
  if (isSubmitted) postData();
}, [isSubmitted]);

// ✅ CORRECT: Execute directly inside the event handler!
function handleSubmit() {
  postData();
}
```

---

## Troubleshooting & Best Practices

1. **Missing Dependencies Warning (`react-hooks/exhaustive-deps`)**
   Never ignore the ESLint exhaustive-deps rule. If a variable or function is referenced inside `useEffect`, it **must** be listed in the dependency array, or moved inside the effect, or stabilized with `useCallback`.

2. **Infinite Re-render Loop**

   ```tsx
   // ❌ INFINITE LOOP: Setting state inside effect with no dependency array
   useEffect(() => {
     setCount(c => c + 1); // Triggers re-render -> runs effect -> triggers re-render...
   });
   ```
