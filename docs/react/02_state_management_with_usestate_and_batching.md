# Module 02: State Management with `useState` & Automatic Batching

**Track:** React — Modern UI & Fiber Architecture
**Category:** Local State, Asynchronous Batching & Immutability

---

## 1. What Is State in React?

Props allow parents to pass data down to children. However, web applications require components to **remember data that changes over time** in response to user input, network events, or timer ticks (e.g. text input values, shopping cart counts, modal open/close flags).

In React, **State** is a component's private, persistent memory. Unlike regular local variables (which reset to their initial values every time a function executes), React preserves state across re-renders.

---

## 2. The `useState` Hook Mechanics

```tsx
const [state, setState] = useState<T>(initialValue);
```

`useState` returns a tuple containing exactly two elements:

1. `state`: The current state snapshot during this render.
2. `setState`: A state setter function that schedules a re-render with a new state value.

```tsx
import { useState } from "react";

export function Counter() {
  const [count, setCount] = useState<number>(0);

  return (
    <div className="counter">
      <p>Current Count: {count}</p>
      <button onClick={() => setCount(count + 1)}>Increment</button>
    </div>
  );
}
```

---

## 3. Lazy Initial State (`useState(() => init)`)

If calculating the initial state requires heavy computation (e.g., reading and parsing a large JSON file from `localStorage` or computing mathematical matrices), **never execute the function directly in the `useState` call**:

```tsx
// ❌ SLOW ANTI-PATTERN: Runs JSON.parse() on EVERY SINGLE RE-RENDER!
// const [items, setItems] = useState(JSON.parse(localStorage.getItem("items") || "[]"));

// ✅ FAST LAZY INITIALIZER: Function runs ONLY ONCE when the component mounts!
const [items, setItems] = useState<string[]>(() => {
  try {
    const raw = localStorage.getItem("items");
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
});
```

---

## 4. Functional State Updates vs Direct Values

Setting state in React is **asynchronous and scheduled**. State variables are snapshots of the *current* render cycle.

### The Stale State Snapshot Bug

```tsx
function BadIncrementer() {
  const [count, setCount] = useState(0);

  function handleTripleClick() {
    // During this render, count is 0:
    setCount(count + 1); // setCount(0 + 1)
    setCount(count + 1); // setCount(0 + 1)
    setCount(count + 1); // setCount(0 + 1)
    // Result after render: count becomes 1, NOT 3!
  }

  return <button onClick={handleTripleClick}>+3</button>;
}
```

### The Solution: Functional Updates (`prev => next`)

When your new state depends on the previous state, pass an **updater function**:

```tsx
function GoodIncrementer() {
  const [count, setCount] = useState(0);

  function handleTripleClick() {
    // React queues these updater functions and processes them sequentially:
    setCount((prev) => prev + 1); // 0 -> 1
    setCount((prev) => prev + 1); // 1 -> 2
    setCount((prev) => prev + 1); // 2 -> 3
    // Result after render: count becomes 3!
  }

  return <button onClick={handleTripleClick}>+3</button>;
}
```

---

## 5. Automatic Batching (React 18+ Concurrent Engine)

**Batching** is when React groups multiple state updates into a single re-render to prevent unnecessary re-rendering and layout thrashing.

### React 17 vs React 18 Batching Behavior

In **React 17**: Only state updates inside React synthetic event handlers (`onClick`, `onChange`) were batched. State updates inside `setTimeout`, `fetch.then()`, or native event listeners triggered multiple re-renders.

In **React 18+**: **Automatic Batching** applies universally across promises, timers, native event handlers, and network callbacks.

```tsx
export function FlightSearch() {
  const [flights, setFlights] = useState<string[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function loadFlights() {
    try {
      const res = await fetch("/api/flights");
      const data = await res.json();

      // In React 18+, these 3 updates are AUTOMATICALLY BATCHED into 1 single re-render!
      setFlights(data);
      setIsLoading(false);
      setError(null);
    } catch (err) {
      setError((err as Error).message);
      setIsLoading(false);
    }
  }

  return <button onClick={loadFlights}>Search Flights</button>;
}
```

### Opting Out of Batching with `flushSync`

In rare scenarios where you need to force an immediate synchronous DOM flush (e.g. measuring an element immediately after state update):

```tsx
import { flushSync } from "react-dom";

function forceImmediateRender() {
  flushSync(() => {
    setCount((c) => c + 1);
  });
  // DOM is guaranteed to be updated synchronously here!
}
```

---

## 6. Immutable State Update Patterns

State in React must be treated as **immutable**. Never mutate objects or arrays in place; always produce fresh copies with updated properties.

### 1. Updating Objects (`{ ...spread }`)

```tsx
interface UserProfile {
  name: string;
  preferences: {
    theme: "light" | "dark";
    emailNotifications: boolean;
  };
}

const [profile, setProfile] = useState<UserProfile>({
  name: "Alice",
  preferences: { theme: "dark", emailNotifications: true },
});

// ✅ Updating top-level and nested properties immutably:
function toggleTheme() {
  setProfile((prev) => ({
    ...prev,
    preferences: {
      ...prev.preferences,
      theme: prev.preferences.theme === "dark" ? "light" : "dark",
    },
  }));
}
```

### 2. Updating Arrays (Adding, Removing, Replacing, Sorting)

```tsx
interface Todo {
  id: string;
  text: string;
  done: boolean;
}

const [todos, setTodos] = useState<Todo[]>([]);

// 1. Add Item (Append)
function addTodo(text: string) {
  const newTodo: Todo = { id: `todo_${Date.now()}`, text, done: false };
  setTodos((prev) => [...prev, newTodo]);
}

// 2. Remove Item (Filter)
function deleteTodo(id: string) {
  setTodos((prev) => prev.filter((todo) => todo.id !== id));
}

// 3. Update Item (Map)
function toggleTodo(id: string) {
  setTodos((prev) =>
    prev.map((todo) => (todo.id === id ? { ...todo, done: !todo.done } : todo))
  );
}

// 4. Sort Items (Array.toSorted() or copy first)
function sortTodosAlphabetically() {
  setTodos((prev) => [...prev].sort((a, b) => a.text.localeCompare(b.text)));
}
```

---

## Troubleshooting & Best Practices

1. **Mutating State In-Place Prevents Re-renders**

   ```tsx
   // ❌ MUTATION: Array reference does not change -> React assumes state is unchanged!
   todos.push(newItem);
   setTodos(todos); // Component WILL NOT RE-RENDER!

   // ✅ CORRECT: Return a new array reference
   setTodos([...todos, newItem]);
   ```

2. **Redundant State Anti-Pattern**
   If a value can be computed from existing props or state, **do not store it in state**. Use a pure computed variable:

   ```tsx
   // ❌ BAD: Storing derived state in useState
   const [items, setItems] = useState<Item[]>([]);
   const [totalPrice, setTotalPrice] = useState<number>(0); // Redundant!

   // ✅ GOOD: Compute on the fly during render
   const [items, setItems] = useState<Item[]>([]);
   const totalPrice = items.reduce((sum, item) => sum + item.price, 0);
   ```
