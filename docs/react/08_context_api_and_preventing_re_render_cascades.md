# Module 08: Context API & Preventing Re-Render Cascades

**Track:** React — Modern UI & Fiber Architecture
**Category:** Global Data Flow, Dependency Injection & Performance Optimization

---

## 1. What Is the Context API and What Problem Does It Solve?

In React, data is typically passed top-down via props. However, when multiple deeply nested components need access to global application state (e.g. Current User, Theme, Localization Locale, Notifications), passing props through 10 intermediate components is called **Prop Drilling**.

**React Context** provides a mechanism to pass data down the component tree without manually threading props at every level:

```text
Without Context (Prop Drilling):
App (has theme) ──► Layout ──► Sidebar ──► NavSection ──► ThemeToggle (uses theme)

With Context (Direct Injection):
App (ThemeProvider) ═════════════════════════════════════► ThemeToggle (useTheme)
```

---

## 2. Basic Context Setup & Type-Safe Custom Hooks

```tsx
// src/context/ThemeContext.tsx
import React, { createContext, useContext, useState, useMemo } from "react";

export type ThemeMode = "light" | "dark" | "system";

export interface ThemeContextValue {
  theme: ThemeMode;
  setTheme: (theme: ThemeMode) => void;
  toggleTheme: () => void;
}

// 1. Create the Context with null default
const ThemeContext = createContext<ThemeContextValue | null>(null);

// 2. Build the Provider Component
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<ThemeMode>("dark");

  const toggleTheme = () => {
    setTheme((prev) => (prev === "dark" ? "light" : "dark"));
  };

  // Memoize the context value to prevent unnecessary re-renders when parent re-renders!
  const value = useMemo(
    () => ({
      theme,
      setTheme,
      toggleTheme,
    }),
    [theme]
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

// 3. Custom Hook with Fail-Fast Safety Guard
export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error("useTheme must be used within a <ThemeProvider />");
  }
  return context;
}
```

---

## 3. The Context Re-render Cascade Problem

A critical architectural pitfall with React Context:

> **When a Context value changes (`Object.is(prevValue, nextValue) === false`), EVERY single component that calls `useContext(MyContext)` MUST re-render**, completely bypassing `React.memo`!

If you bundle your entire application state (user profile, theme, notifications, shopping cart, live WebSocket feeds) into a single giant Context:

- A user typing a single character into a search input in Context triggers a re-render of the navbar, sidebar, profile badge, and heavy charts!

---

## 4. Architectural Solutions to Context Re-render Cascades

### Solution 1: Context Splitting (Separating State & Dispatch)

Because state values change frequently while dispatch/action functions are stable, **split them into two separate contexts**:

```tsx
// src/context/AuthContext.tsx
import React, { createContext, useContext, useReducer } from "react";

interface AuthState {
  user: { id: string; name: string } | null;
  token: string | null;
}

type AuthAction =
  | { type: "LOGIN"; payload: { user: { id: string; name: string }; token: string } }
  | { type: "LOGOUT" };

const AuthStateContext = createContext<AuthState | null>(null);
const AuthDispatchContext = createContext<React.Dispatch<AuthAction> | null>(null);

function authReducer(state: AuthState, action: AuthAction): AuthState {
  switch (action.type) {
    case "LOGIN":
      return { user: action.payload.user, token: action.payload.token };
    case "LOGOUT":
      return { user: null, token: null };
    default:
      return state;
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(authReducer, { user: null, token: null });

  return (
    <AuthStateContext.Provider value={state}>
      <AuthDispatchContext.Provider value={dispatch}>
        {children}
      </AuthDispatchContext.Provider>
    </AuthStateContext.Provider>
  );
}

// Separate hooks for consumers:
export function useAuthState(): AuthState {
  const ctx = useContext(AuthStateContext);
  if (!ctx) throw new Error("useAuthState must be in AuthProvider");
  return ctx;
}

export function useAuthDispatch(): React.Dispatch<AuthAction> {
  const ctx = useContext(AuthDispatchContext);
  if (!ctx) throw new Error("useAuthDispatch must be in AuthProvider");
  return ctx;
}
```

Now, a button that only needs to trigger `dispatch({ type: 'LOGOUT' })` calls `useAuthDispatch()` and **never re-renders when `user` changes**!

---

### Solution 2: Component Composition via `children` (Lifting JSX Up)

Before reaching for Context, you can often eliminate prop drilling entirely by passing components as JSX children:

```tsx
// ❌ Prop Drilling:
<Layout user={user}>
  <Sidebar user={user}>
    <UserMenu user={user} />
  </Sidebar>
</Layout>

// ✅ Component Composition (Zero Prop Drilling & Zero Context needed!):
<Layout
  sidebar={
    <Sidebar>
      <UserMenu user={user} />
    </Sidebar>
  }
/>
```

---

## 5. When to Use Context vs External State Managers (Zustand/Redux)

| Criterion | React Context | Zustand / Redux Toolkit |
| :--- | :--- | :--- |
| **Update Frequency** | Low (Themes, Auth, Locale, Settings) | **High** (Real-time data, complex forms, games) |
| **Selector Subscriptions** | No built-in selector support (All consumers re-render) | **Fine-grained selectors** (`useStore(s => s.count)`) |
| **Devtools Support** | React Devtools tree inspector | Action timelines, state diffs, time travel |
| **Bundle Size** | Built-in (0 KB) | ~1.5 KB (Zustand) |

---

## Troubleshooting & Best Practices

1. **Unstable Context Provider Values**
   Never pass an inline object literal directly to `<Context.Provider value={{ user, token }}>`. Always wrap the value in `useMemo` so downstream components do not re-render on unrelated parent updates.
