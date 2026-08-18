# Module 05: DOM Measurements, `useLayoutEffect` & `useInsertionEffect`

**Track:** React — Modern UI & Fiber Architecture  
**Category:** Layout Synchronization, DOM Metrics & Render Timing

---

## 1. The Visual Flickering Problem: Why `useEffect` Isn't Enough

Consider building a **Tooltip** or **Dropdown Popover** that must position itself relative to a button on screen:

1. React renders the tooltip at `top: 0, left: 0`.
2. React commits the DOM node to the document.
3. The browser **paints** the screen (the user momentarily sees the tooltip flash in the top-left corner).
4. `useEffect` runs asynchronously, measures the button position with `getBoundingClientRect()`, and calls `setPosition({ top: 250, left: 400 })`.
5. React re-renders and the browser paints again.

This visible flash of misplaced content is called **Visual Flickering (Layout Thrashing)**.

---

## 2. `useLayoutEffect` Execution Timing

`useLayoutEffect` has the exact same signature and dependency rules as `useEffect`, but **different execution timing**:

```
Render & Paint Timing Pipeline:
1. Render Phase ──────► Virtual DOM calculated
2. Commit Phase ──────► Real DOM nodes updated / inserted
3. useLayoutEffect ───► Runs SYNCHRONOUSLY BEFORE BROWSER PAINT! ◄── (Measure & Mutate here!)
4. Paint Phase  ──────► Browser paints the final pixel layout to the screen
5. useEffect    ──────► Runs ASYNCHRONOUSLY AFTER Paint
```

Because `useLayoutEffect` runs **synchronously before the browser paints**, any state updates scheduled inside it are flushed immediately before the user sees the first frame. **Zero visual flicker.**

---

## 3. Practical Example: Auto-Positioning Tooltip

```tsx
import { useState, useRef, useLayoutEffect } from "react";

export function AutoPositionTooltip({
  targetRef,
  text,
}: {
  targetRef: React.RefObject<HTMLElement>;
  text: string;
}) {
  const tooltipRef = useRef<HTMLDivElement>(null);
  const [coords, setCoords] = useState<{ top: number; left: number }>({ top: 0, left: 0 });

  useLayoutEffect(() => {
    if (!targetRef.current || !tooltipRef.current) return;

    const targetRect = targetRef.current.getBoundingClientRect();
    const tooltipRect = tooltipRef.current.getBoundingClientRect();

    // Calculate centered position above target element:
    const top = targetRect.top - tooltipRect.height - 8; // 8px margin
    const left = targetRect.left + (targetRect.width / 2) - (tooltipRect.width / 2);

    setCoords({
      top: Math.max(0, top),
      left: Math.max(0, left),
    });
  }, [targetRef]);

  return (
    <div
      ref={tooltipRef}
      className="tooltip-floating"
      style={{
        position: "fixed",
        top: `${coords.top}px`,
        left: `${coords.left}px`,
        pointerEvents: "none",
        zIndex: 9999,
      }}
    >
      {text}
    </div>
  );
}
```

---

## 4. `useLayoutEffect` in SSR & `useIsomorphicLayoutEffect`

In Server-Side Rendering (SSR) environments (Next.js, Remix, Astro), `useLayoutEffect` generates a console warning:

> `Warning: useLayoutEffect does nothing on the server, because its effect cannot be encoded into the server renderer's output format.`

To build isomorphic components that work on both server and client without warnings:

```typescript
// src/hooks/useIsomorphicLayoutEffect.ts
import { useEffect, useLayoutEffect } from "react";

// Evaluates to useLayoutEffect in the browser, and useEffect during SSR:
export const useIsomorphicLayoutEffect =
  typeof window !== "undefined" ? useLayoutEffect : useEffect;
```

---

## 5. `useInsertionEffect` (React 18+ for CSS-in-JS Libraries)

Introduced in React 18, **`useInsertionEffect`** executes **before any DOM mutations occur**. 

It is designed exclusively for CSS-in-JS library authors (such as styled-components or Emotion) to inject `<style>` tags or CSS rules into the document `<head>` before the layout is computed, avoiding recalculating styles during layout measurement:

```typescript
import { useInsertionEffect } from "react";

export function useDynamicStyle(cssRule: string) {
  useInsertionEffect(() => {
    const styleElement = document.createElement("style");
    styleElement.textContent = cssRule;
    document.head.appendChild(styleElement);

    return () => {
      document.head.removeChild(styleElement);
    };
  }, [cssRule]);
}
```

*Note: Application developers should almost never use `useInsertionEffect`. It is intended strictly for library authors.*

---

## 6. Comparison Table: Effect Hooks

| Hook | Execution Timing | Blocks Browser Paint? | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **`useEffect`** | **After Paint** (Asynchronous) | **No** | Data fetching, event subscriptions, logging, timers (95% of use cases) |
| **`useLayoutEffect`** | **Before Paint** (Synchronous) | **Yes** | DOM measurements, scroll positioning, tooltip placement |
| **`useInsertionEffect`** | **Before DOM Mutation** | **Yes** | CSS-in-JS `<style>` injection |

---

## Troubleshooting & Best Practices

1. **Do not perform heavy computations in `useLayoutEffect`**
   Because `useLayoutEffect` runs synchronously before the browser paints, heavy computations or blocking loops will freeze the main UI thread and drop frame rates to 0 fps. Always prefer `useEffect` unless measuring DOM dimensions is strictly required.