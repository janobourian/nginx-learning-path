# Module 07: Persistent Mutable References — `useRef`, `forwardRef` & `useImperativeHandle`

**Track:** React — Modern UI & Fiber Architecture  
**Category:** DOM Access, Mutable References & Imperative Handles

---

## 1. What Is `useRef` in React?

`useRef` is a built-in React hook that returns a plain JavaScript object with a single mutable property: **`.current`**:

```typescript
const ref = useRef<T>(initialValue); // Returns { current: initialValue }
```

`useRef` has two distinct superpowers:
1. **Accessing and manipulating real DOM nodes directly** (e.g. focusing an input, scrolling to an element, measuring a canvas).
2. **Storing mutable state across renders without triggering a re-render** when mutated.

---

## 2. Comparing `useRef`, `useState`, and Local Variables

| Aspect | `useState` | `useRef` | Plain Local Variable |
| :--- | :--- | :--- | :--- |
| **Persists Across Renders?** | **Yes** | **Yes** | **No** (Resets every render) |
| **Mutating Triggers Re-render?** | **Yes** (`setState()`) | **No** (`ref.current = x`) | **No** |
| **Reading Value** | `state` | `ref.current` | `variable` |
| **Primary Purpose** | Visual data driving UI rendering | Persistent non-visual data & DOM refs | Temporary transient calculations |

---

## 3. DOM Node Manipulation with `useRef`

```tsx
import { useRef, useEffect } from "react";

export function AutoFocusSearchForm() {
  // 1. Declare ref with explicit DOM element type
  const inputRef = useRef<HTMLInputElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    // 2. Access real DOM node via .current after mount
    inputRef.current?.focus();
  }, []);

  function handlePlayVideo() {
    videoRef.current?.play();
  }

  return (
    <div>
      <input ref={inputRef} type="text" placeholder="Search..." />
      <video ref={videoRef} src="/promo.mp4" width={400} />
      <button onClick={handlePlayVideo}>Play Video</button>
    </div>
  );
}
```

---

## 4. Storing Non-Visual Mutable State (Timers & Previous State)

### 1. Managing Timer & Interval IDs

```tsx
import { useState, useRef, useEffect } from "react";

export function Stopwatch() {
  const [seconds, setSeconds] = useState(0);
  const [isRunning, setIsRunning] = useState(false);

  // Store the setInterval ID in a ref so it persists without causing re-renders
  const timerRef = useRef<number | null>(null);

  function start() {
    if (timerRef.current !== null) return;
    setIsRunning(true);
    timerRef.current = window.setInterval(() => {
      setSeconds((s) => s + 1);
    }, 1000);
  }

  function pause() {
    if (timerRef.current !== null) {
      clearInterval(timerRef.current);
      timerRef.current = null;
      setIsRunning(false);
    }
  }

  function reset() {
    pause();
    setSeconds(0);
  }

  // Always clean up timers on unmount!
  useEffect(() => {
    return () => {
      if (timerRef.current !== null) clearInterval(timerRef.current);
    };
  }, []);

  return (
    <div>
      <h2>Elapsed: {seconds}s</h2>
      <button onClick={start} disabled={isRunning}>Start</button>
      <button onClick={pause} disabled={!isRunning}>Pause</button>
      <button onClick={reset}>Reset</button>
    </div>
  );
}
```

### 2. Building a `usePrevious` Hook

```typescript
import { useRef, useEffect } from "react";

export function usePrevious<T>(value: T): T | undefined {
  const ref = useRef<T>();

  useEffect(() => {
    // Update ref AFTER render completes:
    ref.current = value;
  }, [value]);

  // Returns the value from the PREVIOUS render cycle:
  return ref.current;
}
```

---

## 5. Forwarding Refs to Child Components (`forwardRef`)

By default, React components **cannot accept a `ref` prop**. If a parent attempts to pass a ref to a custom child component, React throws a warning.

Use **`React.forwardRef`** to expose a child's inner DOM node to the parent:

```tsx
import React, { forwardRef } from "react";

export interface CustomInputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
  errorMessage?: string;
}

export const CustomInput = forwardRef<HTMLInputElement, CustomInputProps>(
  function CustomInput({ label, errorMessage, ...rest }, ref) {
    return (
      <div className="form-group">
        <label>{label}</label>
        <input ref={ref} className="form-input" {...rest} />
        {errorMessage && <span className="error">{errorMessage}</span>}
      </div>
    );
  }
);
```

---

## 6. Custom Imperative Handles with `useImperativeHandle`

Instead of exposing the raw DOM node directly to parent components, you can use **`useImperativeHandle`** to expose a **custom, restricted imperative API**:

```tsx
import React, { forwardRef, useRef, useImperativeHandle, useState } from "react";

// The exposed public interface for the parent:
export interface ModalHandle {
  open: () => void;
  close: () => void;
  isOpen: boolean;
}

export const AdvancedModal = forwardRef<ModalHandle, { title: string; children: React.ReactNode }>(
  function AdvancedModal({ title, children }, ref) {
    const [isOpen, setIsOpen] = useState(false);

    // Customize the object exposed via ref.current:
    useImperativeHandle(ref, () => ({
      open() {
        setIsOpen(true);
      },
      close() {
        setIsOpen(false);
      },
      get isOpen() {
        return isOpen;
      },
    }), [isOpen]);

    if (!isOpen) return null;

    return (
      <div className="modal-backdrop">
        <div className="modal-card">
          <h3>{title}</h3>
          <div>{children}</div>
          <button onClick={() => setIsOpen(false)}>Close</button>
        </div>
      </div>
    );
  }
);
```

```tsx
// Parent component consuming the ModalHandle:
export function ParentView() {
  const modalRef = useRef<ModalHandle>(null);

  return (
    <div>
      <button onClick={() => modalRef.current?.open()}>Open Modal</button>
      <AdvancedModal ref={modalRef} title="Terms of Service">
        <p>Please review our security policy...</p>
      </AdvancedModal>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Do NOT read or write `ref.current` during the Render Phase**
   Writing `ref.current = x` in the body of a component during render violates React's purity rules and causes unpredictable behavior in Concurrent Mode. Only read/write `ref.current` inside `useEffect`, `useLayoutEffect`, or event handlers.