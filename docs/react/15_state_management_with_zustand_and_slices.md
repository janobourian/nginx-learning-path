# Module 15: Global State Management with Zustand & the Slices Pattern

**Track:** React — Modern UI & Fiber Architecture
**Category:** Global State Architecture, Fine-Grained Selectors & Middleware

---

## 1. What Is Zustand and Why Did It Win the React Ecosystem?

While Redux Toolkit (RTK) is powerful for large enterprise legacy systems and React Context works for simple low-frequency settings, **Zustand** (German for "State") has emerged as the modern gold standard for React state management.

### Why Developers Choose Zustand

1. **Zero Boilerplate**: No Providers (`<StoreProvider>`), no reducers, no action creators, no context wrapping.
2. **Fine-Grained Selector Subscriptions**: Components only re-render when the **specifically selected slice of state** changes (`useStore(s => s.user.name)`).
3. **Ultra-Lightweight**: **~1.1 KB** minified and gzipped (compared to Redux Toolkit's ~30KB).
4. **Usable Outside React Components**: State can be read and mutated anywhere (utility functions, event listeners, API interceptors) via `useStore.getState()` and `useStore.setState()`.

---

## 2. Basic Zustand Store Setup

```bash
npm install zustand
```

```typescript
// src/stores/useCounterStore.ts
import { create } from "zustand";

interface CounterState {
  count: number;
  increment: () => void;
  decrement: () => void;
  reset: () => void;
  setCustom: (val: number) => void;
}

export const useCounterStore = create<CounterState>()((set) => ({
  count: 0,
  increment: () => set((state) => ({ count: state.count + 1 })),
  decrement: () => set((state) => ({ count: state.count - 1 })),
  reset: () => set({ count: 0 }),
  setCustom: (val) => set({ count: val }),
}));
```

### Consuming the Store with Selectors

```tsx
import { useCounterStore } from "@/stores/useCounterStore";

export function CounterDisplay() {
  // Fine-grained selector: Component ONLY re-renders when count changes!
  const count = useCounterStore((state) => state.count);

  return <h1>Count: {count}</h1>;
}

export function CounterControls() {
  // Extracting actions: Actions are stable functions that never trigger re-renders!
  const increment = useCounterStore((state) => state.increment);
  const decrement = useCounterStore((state) => state.decrement);

  return (
    <div>
      <button onClick={decrement}>-</button>
      <button onClick={increment}>+</button>
    </div>
  );
}
```

---

## 3. Asynchronous Actions & Side Effects in Zustand

In Zustand, actions can be asynchronous `async/await` functions with direct access to `set` and `get`:

```typescript
// src/stores/useUserStore.ts
import { create } from "zustand";

export interface User {
  id: string;
  name: string;
  email: string;
}

interface UserStoreState {
  user: User | null;
  isLoading: boolean;
  error: string | null;
  fetchUser: (userId: string) => Promise<void>;
  logout: () => void;
}

export const useUserStore = create<UserStoreState>()((set, get) => ({
  user: null,
  isLoading: false,
  error: null,

  fetchUser: async (userId: string) => {
    // Access current state via get() if needed:
    if (get().isLoading) return;

    set({ isLoading: true, error: null });
    try {
      const res = await fetch(`/api/users/${userId}`);
      if (!res.ok) throw new Error("Failed to fetch user");
      const user = await res.json();
      set({ user, isLoading: false });
    } catch (err) {
      set({ error: (err as Error).message, isLoading: false });
    }
  },

  logout: () => set({ user: null }),
}));
```

---

## 4. The Slices Pattern (Modular Enterprise State Architecture)

In large enterprise applications with hundreds of state fields, maintaining a single giant store file is unmaintainable. The **Slices Pattern** splits state into domain-specific slices that compose into a single unified root store.

```text
Monolithic Store Split into Slices:
┌────────────────────────────────────────────────────────┐
│                      Root Store                        │
│  ┌───────────────────┬───────────────────┬──────────┐  │
│  │    Auth Slice     │    Cart Slice     │ UI Slice │  │
│  └───────────────────┴───────────────────┴──────────┘  │
└────────────────────────────────────────────────────────┘
```

### 1. Defining Slices (`StateCreator`)

```typescript
// src/stores/slices/createAuthSlice.ts
import { type StateCreator } from "zustand";
import { type RootStore } from "../useRootStore";

export interface AuthSlice {
  token: string | null;
  isAuthenticated: boolean;
  login: (token: string) => void;
  logout: () => void;
}

export const createAuthSlice: StateCreator<RootStore, [], [], AuthSlice> = (set) => ({
  token: null,
  isAuthenticated: false,
  login: (token) => set({ token, isAuthenticated: true }),
  logout: () => set({ token: null, isAuthenticated: false }),
});
```

```typescript
// src/stores/slices/createCartSlice.ts
import { type StateCreator } from "zustand";
import { type RootStore } from "../useRootStore";

export interface CartItem {
  id: string;
  name: string;
  price: number;
}

export interface CartSlice {
  cart: CartItem[];
  addToCart: (item: CartItem) => void;
  clearCart: () => void;
}

export const createCartSlice: StateCreator<RootStore, [], [], CartSlice> = (set) => ({
  cart: [],
  addToCart: (item) => set((state) => ({ cart: [...state.cart, item] })),
  clearCart: () => set({ cart: [] }),
});
```

### 2. Composing Slices into the Root Store

```typescript
// src/stores/useRootStore.ts
import { create } from "zustand";
import { createAuthSlice, type AuthSlice } from "./slices/createAuthSlice";
import { createCartSlice, type CartSlice } from "./slices/createCartSlice";

export type RootStore = AuthSlice & CartSlice;

export const useRootStore = create<RootStore>()((...a) => ({
  ...createAuthSlice(...a),
  ...createCartSlice(...a),
}));
```

---

## 5. Middleware: `persist` & `devtools`

Zustand includes powerful middleware for local storage caching and Redux DevTools debugging:

```typescript
import { create } from "zustand";
import { persist, createJSONStorage, devtools } from "zustand/middleware";
import { immer } from "zustand/middleware/immer";

export interface AppSettingsState {
  theme: "light" | "dark";
  sidebarCollapsed: boolean;
  toggleTheme: () => void;
}

export const useSettingsStore = create<AppSettingsState>()(
  devtools(
    persist(
      (set) => ({
        theme: "dark",
        sidebarCollapsed: false,
        toggleTheme: () =>
          set(
            (state) => ({ theme: state.theme === "dark" ? "light" : "dark" }),
            false,
            "settings/toggleTheme" // Action name for Redux DevTools
          ),
      }),
      {
        name: "app_settings_cache", // LocalStorage key
        storage: createJSONStorage(() => localStorage),
      }
    )
  )
);
```

---

## 6. Accessing Zustand Outside React Components

You can read or mutate Zustand state in non-React code (e.g. Axios request interceptors, logging services):

```typescript
// src/lib/apiClient.ts
import { useRootStore } from "@/stores/useRootStore";

export async function secureFetch(url: string) {
  // Read state outside of React without hooks:
  const token = useRootStore.getState().token;

  const response = await fetch(url, {
    headers: {
      Authorization: token ? `Bearer ${token}` : "",
    },
  });

  if (response.status === 401) {
    // Mutate state outside React:
    useRootStore.getState().logout();
  }

  return response;
}
```

---

## Troubleshooting & Best Practices

1. **Avoid Destructuring Without Selectors**

   ```tsx
   // ❌ BAD: Destructuring the whole store causes component to re-render on ANY change!
   const { count, user, cart } = useRootStore();

   // ✅ GOOD: Use individual selectors
   const count = useRootStore((s) => s.count);
   const user = useRootStore((s) => s.user);
   ```

2. **Selecting Multiple Values with `useShallow`**
   If you must select multiple properties in a single selector, use `useShallow` to prevent false re-renders:

   ```tsx
   import { useShallow } from "zustand/react/shallow";

   const { name, email } = useRootStore(
     useShallow((s) => ({ name: s.user?.name, email: s.user?.email }))
   );
   ```
