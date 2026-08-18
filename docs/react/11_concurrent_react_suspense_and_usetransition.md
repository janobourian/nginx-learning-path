# Module 11: Concurrent React — `useTransition`, `Suspense` & Priority Scheduling

**Track:** React — Modern UI & Fiber Architecture  
**Category:** Concurrent Features, Priority Queues & Suspense Architecture

---

## 1. What Is Concurrent React?

In standard synchronous rendering, React processes updates in order of arrival. If a heavy update (e.g. rendering 10,000 table rows) takes 200ms, the entire browser UI freezes. If the user tries to type into an `<input>` during those 200ms, keystrokes are dropped or delayed.

**Concurrent React** (introduced in React 18 and enhanced in React 19) introduces **Priority-Based Interruptible Scheduling**.

React categorizes updates into two priority levels:
1. **Urgent Updates**: Direct user physical interactions (typing into inputs, hovering, clicking buttons). These must respond immediately (< 16ms) to feel responsive.
2. **Transition Updates (Non-Urgent)**: Navigating tabs, filtering a search result list, rendering complex analytics charts. These can yield to urgent inputs and render in the background.

```
Concurrent Priority Interruption:
[User Types Keystroke 'A'] ──► (URGENT PRIORITY: Interrupts ongoing background work!)
                                       │
                                       ▼ (Input updates instantly on screen)
[Background Search Filter] ◄── (NON-URGENT: Pauses, discards stale work, resumes with new query)
```

---

## 2. The `useTransition` Hook

`useTransition` marks a state update as a **non-urgent transition**, keeping the UI fully interactive while the next screen prepares in the background:

```tsx
const [isPending, startTransition] = useTransition();
```

- `isPending`: Boolean flag indicating whether the transition is currently being processed in a background Fiber tree.
- `startTransition`: Wraps state updates to execute at low priority without blocking user interactions.

---

## 3. Practical Example: Non-Blocking Tab Navigation

```tsx
import { useState, useTransition } from "react";
import { HeavyAnalyticsTab } from "./HeavyAnalyticsTab";
import { OverviewTab } from "./OverviewTab";
import { SettingsTab } from "./SettingsTab";

export function AdminDashboard() {
  const [activeTab, setActiveTab] = useState<"overview" | "analytics" | "settings">("overview");
  const [isPending, startTransition] = useTransition();

  function handleTabSwitch(nextTab: "overview" | "analytics" | "settings") {
    // Wrap the state update in a transition:
    startTransition(() => {
      setActiveTab(nextTab);
    });
  }

  return (
    <div className="dashboard-container">
      <nav className="tab-navigation">
        <button
          className={activeTab === "overview" ? "active" : ""}
          onClick={() => handleTabSwitch("overview")}
        >
          Overview
        </button>

        <button
          className={activeTab === "analytics" ? "active" : ""}
          onClick={() => handleTabSwitch("analytics")}
        >
          Analytics {isPending && activeTab !== "analytics" && <span className="spinner-inline" />}
        </button>

        <button
          className={activeTab === "settings" ? "active" : ""}
          onClick={() => handleTabSwitch("settings")}
        >
          Settings
        </button>
      </nav>

      {/* When switching to heavy analytics, the old tab stays visible and responsive while the new tab renders in the background! */}
      <div className={`tab-content ${isPending ? "tab-content--dimmed" : ""}`}>
        {activeTab === "overview" && <OverviewTab />}
        {activeTab === "analytics" && <HeavyAnalyticsTab />}
        {activeTab === "settings" && <SettingsTab />}
      </div>
    </div>
  );
}
```

---

## 4. `useDeferredValue` (Deferring Child Re-renders)

While `useTransition` wraps the *state setter function*, **`useDeferredValue`** wraps a *state value or prop* when you don't own the state setter:

```tsx
import { useState, useDeferredValue, useMemo } from "react";

export function SearchFilterView() {
  const [query, setQuery] = useState("");

  // Urgent: query updates immediately to keep typing input responsive (<16ms)
  // Deferred: deferredQuery lags behind until the main thread is idle!
  const deferredQuery = useDeferredValue(query);

  const isStale = query !== deferredQuery;

  return (
    <div>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Type to search..."
      />

      <div style={{ opacity: isStale ? 0.6 : 1 }}>
        {/* Heavy list uses the deferred value */}
        <SlowProductList search={deferredQuery} />
      </div>
    </div>
  );
}
```

---

## 5. `<Suspense>` in Concurrent React

`<Suspense>` lets you declare a fallback loading state for any child component tree that is waiting for an asynchronous operation (data fetch, code-split dynamic import).

```tsx
import { Suspense, lazy } from "react";

// Code splitting via React.lazy
const HeavyChart = lazy(() => import("./HeavyChart"));

export function MetricsSection() {
  return (
    <div className="metrics-box">
      <h2>Quarterly Revenue</h2>

      <Suspense fallback={<div className="skeleton-box">Loading Chart Engine...</div>}>
        <HeavyChart />
      </Suspense>
    </div>
  );
}
```

### The `React.use()` API (React 19)

In React 19, the new **`use()`** hook allows unwrapping Promises directly inside component render functions, automatically integrating with `<Suspense>` boundaries:

```tsx
// React 19: Unwrapping a Promise directly in render!
import { use, Suspense } from "react";

interface UserProfile {
  name: string;
  email: string;
}

function UserCard({ userPromise }: { userPromise: Promise<UserProfile> }) {
  // 'use()' suspends the component until the Promise resolves!
  const user = use(userPromise);

  return (
    <div className="user-card">
      <h3>{user.name}</h3>
      <p>{user.email}</p>
    </div>
  );
}

export function App({ userPromise }: { userPromise: Promise<UserProfile> }) {
  return (
    <Suspense fallback={<p>Fetching user details...</p>}>
      <UserCard userPromise={userPromise} />
    </Suspense>
  );
}
```

---

## 6. Error Boundaries (`componentDidCatch`)

When an async component or Suspense boundary fails, an **Error Boundary** catches the error and displays a graceful fallback UI instead of crashing the entire application:

```tsx
import React, { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("[ErrorBoundary caught error]:", error, errorInfo);
    // Send to Sentry / Datadog telemetry here
  }

  public render() {
    if (this.state.hasError) {
      return (
        this.props.fallback ?? (
          <div className="error-fallback">
            <h2>Something went wrong.</h2>
            <p>{this.state.error?.message}</p>
            <button onClick={() => this.setState({ hasError: false, error: null })}>
              Try Again
            </button>
          </div>
        )
      );
    }

    return this.props.children;
  }
}
```

---

## Troubleshooting & Best Practices

1. **Do not use `startTransition` for controlled text inputs**
   Never wrap an `<input>`'s direct `onChange` state update in `startTransition`. Deferring controlled input state causes input cursor jumping and stuttering. Only defer the *downstream* filtering or navigation state.