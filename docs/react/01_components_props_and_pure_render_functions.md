# Module 01: Components, Props & Pure Render Functions

**Track:** React — Modern UI & Fiber Architecture
**Category:** Component Fundamentals, Prop Interfaces & Render Purity

---

## 1. Components as Pure Functions

In React, a **Function Component** is a JavaScript function that accepts an input object called **`props`** (properties) and returns a description of the UI as JSX (React Elements).

The core tenet of React's architecture is **Component Purity**:

> **A React component must behave like a pure mathematical function:**
> Given the exact same inputs (`props` and `state`), it must always return the exact same output (JSX), and rendering must cause **zero side effects**.

```tsx
// Pure Component: No side effects, deterministic output
export function UserBadge({ username, role }: { username: string; role: "admin" | "user" }) {
  return (
    <span className={`badge badge--${role}`}>
      {username} {role === "admin" && "★"}
    </span>
  );
}
```

---

## 2. Defining Typed Props with TypeScript

In modern TypeScript, define component props using an explicit `interface` or `type` alias:

```tsx
import React from "react";

export interface ButtonProps {
  // Mandatory props
  label: string;
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;

  // Optional props with unions
  variant?: "primary" | "secondary" | "danger" | "ghost";
  size?: "sm" | "md" | "lg";
  disabled?: boolean;
  isLoading?: boolean;

  // Children prop for slot-like composition
  children?: React.ReactNode;

  // Icon element slot
  icon?: React.ReactElement;
}

export function Button({
  label,
  onClick,
  variant = "primary", // Default prop via destructuring
  size = "md",
  disabled = false,
  isLoading = false,
  children,
  icon,
}: ButtonProps) {
  return (
    <button
      className={`btn btn--${variant} btn--${size} ${isLoading ? "btn--loading" : ""}`}
      onClick={onClick}
      disabled={disabled || isLoading}
    >
      {isLoading ? (
        <span className="spinner" />
      ) : (
        <>
          {icon && <span className="btn__icon">{icon}</span>}
          <span className="btn__label">{children ?? label}</span>
        </>
      )}
    </button>
  );
}
```

---

## 3. The `children` Prop & Compound Components

`React.ReactNode` represents anything that can be rendered in JSX: strings, numbers, elements, fragments, arrays of nodes, or `null`.

```tsx
export interface CardProps {
  title: string;
  headerAction?: React.ReactNode;
  children: React.ReactNode; // Embedded card body content
  footer?: React.ReactNode;
}

export function Card({ title, headerAction, children, footer }: CardProps) {
  return (
    <article className="card">
      <header className="card__header">
        <h3 className="card__title">{title}</h3>
        {headerAction && <div className="card__action">{headerAction}</div>}
      </header>

      <div className="card__body">{children}</div>

      {footer && <footer className="card__footer">{footer}</footer>}
    </article>
  );
}
```

---

## 4. Immutability of Props: Why Props Are Read-Only

Props in React represent **external state owned by the parent component**. A child component must **never mutate its props**:

```tsx
// ❌ DANGEROUS ANTI-PATTERN: Mutating props directly!
export function BadComponent(props: { items: string[] }) {
  // props.items.push("new"); // Mutates parent's state object in place!
  // props.title = "Modified"; // Throws runtime error in strict mode!
  return <div>{props.items.length}</div>;
}

// ✅ CORRECT: If state needs to change, pass an event callback up to the parent:
export function GoodComponent({
  items,
  onAddItem,
}: {
  items: readonly string[];
  onAddItem: (newItem: string) => void;
}) {
  return (
    <div>
      <button onClick={() => onAddItem("new_item")}>Add Item</button>
      <ul>
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </div>
  );
}
```

---

## 5. The Rules of Purity in React

During the **Render Phase**, React executes your component function to construct the virtual tree. React can call your component function multiple times, pause it, or abort it in concurrent mode.

### What is Forbidden During Rendering

1. **Mutating Pre-existing Variables / Objects**:

   ```tsx
   // ❌ MUTATION ANTI-PATTERN:
   let guestCount = 0; // External variable
   function Cup() {
     guestCount = guestCount + 1; // Side-effect mutation during render!
     return <h2>Tea cup for guest #{guestCount}</h2>;
   }
   ```

2. **Performing Network Requests (`fetch()`) in the Component Body**:
   Network calls belong inside `useEffect()` or event handlers, never naked in the render body.

3. **Setting Timers (`setTimeout`, `setInterval`) Directly in the Body**:
   Creates thousands of orphaned timers on every re-render.

4. **Mutating the Real DOM Directly (`document.body.appendChild(...)`)**:
   Breaks React's reconciliation engine.

### Safe Operations During Rendering

- **Local Variable Mutation**: Mutating variables created *inside* the current render function is 100% pure because no other component can observe them:

  ```tsx
  export function ShoppingList({ items }: { items: string[] }) {
    const listItems = []; // Created locally during this render
    for (let i = 0; i < items.length; i++) {
      listItems.push(<li key={i}>{items[i]}</li>); // Pure!
    }
    return <ul>{listItems}</ul>;
  }
  ```

---

## 6. Container vs Presentational Component Architecture

In enterprise React codebases, separate your components into two distinct layers:

```text
┌─────────────────────────────────────────────────────────────┐
│              Container Component (Smart / Stateful)         │
│  • Manages useState, useQuery, custom hooks                 │
│  • Performs API calls and data transformation               │
│  • Zero CSS/Styling logic                                   │
└──────────────────────────────┬──────────────────────────────┘
                               │ Passes Props & Callbacks
                               ▼
┌─────────────────────────────────────────────────────────────┐
│           Presentational Component (Dumb / Pure UI)         │
│  • Pure function of props                                   │
│  • Highly reusable and easily unit tested                   │
│  • Owns CSS classes and UI layout                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting & Best Practices

1. **Missing Prop Types or Overusing `any`**
   Always type props with exact TypeScript interfaces. Never use `React.FC` without generic props or untyped `props: any`.

2. **Conditional Rendering Gotcha with `0`**
   In JavaScript, `0 && <Component />` evaluates to `0` (which React renders as a literal `"0"` text on screen!). Always convert numbers to booleans:

   ```tsx
   // ❌ Renders '0' on screen when count is 0:
   // {count && <MessageList count={count} />}

   // ✅ Correct:
   {count > 0 && <MessageList count={count} />}
   ```
