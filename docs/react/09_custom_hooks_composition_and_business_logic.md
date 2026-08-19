# Module 09: Custom Hooks — Composition, Architecture & Reusable Logic

**Track:** React — Modern UI & Fiber Architecture
**Category:** Logic Extraction, Reusable Hooks & Design Patterns

---

## 1. What Is a Custom Hook?

In React, components encapsulate UI rendering, while **Custom Hooks** encapsulate and share **stateful logic** between components.

A custom hook is simply a JavaScript function whose name starts with **`use`** (e.g. `useFetch`, `useDebounce`, `useLocalStorage`) that can call other React hooks (`useState`, `useEffect`, `useRef`, `useCallback`).

Whenever two components use the same custom hook, **each component gets completely independent, isolated state**.

---

## 2. The Rules of Hooks

To allow React to track which state belongs to which hook across re-renders (using Fiber linked lists), you must adhere to the **Two Golden Rules of Hooks**:

1. **Only Call Hooks at the Top Level**:

   - Do **not** call hooks inside loops (`for`), conditions (`if`), or nested functions.
   - This guarantees that hooks are called in the exact same order on every render.
2. **Only Call Hooks from React Functions**:

   - Call hooks from React function components or other custom hooks. Never call hooks from regular utility functions.

---

## 3. Production Custom Hook Suite

### 1. `useDebounce<T>` (Delaying Expensive Search/API Calls)

```typescript
// src/hooks/useDebounce.ts
import { useState, useEffect } from "react";

export function useDebounce<T>(value: T, delayMs: number = 300): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedValue(value);
    }, delayMs);

    // Cleanup: Cancel timer if value changes before delay expires!
    return () => {
      clearTimeout(timer);
    };
  }, [value, delayMs]);

  return debouncedValue;
}
```

### 2. `useIntersectionObserver` (Infinite Scrolling & Lazy Loading)

```typescript
// src/hooks/useIntersectionObserver.ts
import { useState, useEffect, type RefObject } from "react";

export function useIntersectionObserver(
  targetRef: RefObject<Element>,
  options: IntersectionObserverInit = { threshold: 0.1 }
): boolean {
  const [isIntersecting, setIsIntersecting] = useState(false);

  useEffect(() => {
    const element = targetRef.current;
    if (!element || typeof IntersectionObserver === "undefined") return;

    const observer = new IntersectionObserver(([entry]) => {
      if (entry) {
        setIsIntersecting(entry.isIntersecting);
      }
    }, options);

    observer.observe(element);

    return () => {
      observer.disconnect();
    };
  }, [targetRef, options.threshold, options.root, options.rootMargin]);

  return isIntersecting;
}
```

### 3. `useMediaQuery` (Reactive CSS Media Queries)

```typescript
// src/hooks/useMediaQuery.ts
import { useState, useEffect } from "react";

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return window.matchMedia(query).matches;
  });

  useEffect(() => {
    if (typeof window === "undefined") return;

    const mediaQueryList = window.matchMedia(query);
    const listener = (event: MediaQueryListEvent) => {
      setMatches(event.matches);
    };

    mediaQueryList.addEventListener("change", listener);
    setMatches(mediaQueryList.matches);

    return () => {
      mediaQueryList.removeEventListener("change", listener);
    };
  }, [query]);

  return matches;
}
```

### 4. `useLocalStorage` with Cross-Tab Synchronization

```typescript
// src/hooks/useLocalStorage.ts
import { useState, useEffect, useCallback } from "react";

export function useLocalStorage<T>(
  key: string,
  initialValue: T
): [T, (value: T | ((prev: T) => T)) => void] {
  const readValue = useCallback((): T => {
    if (typeof window === "undefined") return initialValue;
    try {
      const item = window.localStorage.getItem(key);
      return item ? (JSON.parse(item) as T) : initialValue;
    } catch {
      return initialValue;
    }
  }, [key, initialValue]);

  const [storedValue, setStoredValue] = useState<T>(readValue);

  const setValue = useCallback(
    (value: T | ((prev: T) => T)) => {
      try {
        const newValue = value instanceof Function ? value(storedValue) : value;
        if (typeof window !== "undefined") {
          window.localStorage.setItem(key, JSON.stringify(newValue));
        }
        setStoredValue(newValue);
      } catch (err) {
        console.error(`Error saving to localStorage key "${key}":`, err);
      }
    },
    [key, storedValue]
  );

  // Sync across different browser tabs via 'storage' window event:
  useEffect(() => {
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === key && e.newValue !== null) {
        try {
          setStoredValue(JSON.parse(e.newValue));
        } catch {
          // ignore corrupted data
        }
      }
    };

    window.addEventListener("storage", handleStorageChange);
    return () => window.removeEventListener("storage", handleStorageChange);
  }, [key]);

  return [storedValue, setValue];
}
```

---

## 4. Consuming Custom Hooks in Components

```tsx
import { useRef } from "react";
import { useDebounce } from "@/hooks/useDebounce";
import { useIntersectionObserver } from "@/hooks/useIntersectionObserver";
import { useMediaQuery } from "@/hooks/useMediaQuery";

export function SearchAndInfiniteFeed() {
  const [searchTerm, setSearchTerm] = useState("");
  const debouncedSearch = useDebounce(searchTerm, 400);

  const isMobile = useMediaQuery("(max-width: 768px)");

  const loadMoreTriggerRef = useRef<HTMLDivElement>(null);
  const isTriggerVisible = useIntersectionObserver(loadMoreTriggerRef);

  useEffect(() => {
    if (isTriggerVisible) {
      console.log("Load next page of results for:", debouncedSearch);
    }
  }, [isTriggerVisible, debouncedSearch]);

  return (
    <div className={`feed-layout ${isMobile ? "mobile" : "desktop"}`}>
      <input
        value={searchTerm}
        onChange={(e) => setSearchTerm(e.target.value)}
        placeholder="Type to search..."
      />

      <p>Debounced API Query: <strong>{debouncedSearch}</strong></p>

      {/* Infinite Scroll sentinel trigger */}
      <div ref={loadMoreTriggerRef} className="scroll-sentinel">
        {isTriggerVisible ? "Loading more..." : "Scroll down to load"}
      </div>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Return Formats: Tuples vs Objects**

   - Use **Tuples (`[state, setter]`)** when the hook mimics `useState` (1-2 values) so consumers can name them freely (`const [name, setName] = useLocalStorage(...)`).
   - Use **Objects (`{ data, error, isLoading, refetch }`)** when the hook returns 3+ properties to allow named destructuring without order dependency.
