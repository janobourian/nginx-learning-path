# Module 10: Composition API & Custom Composables

**Track:** Vue — Progressive Web Framework  
**Category:** Logic Reuse & Architecture

---

## What Is a Composable?

In the context of Vue applications, a **composable** is a function that leverages Vue's Composition API to encapsulate and reuse **stateful logic**. 

Unlike simple utility functions (which take inputs, perform computations, and return pure outputs), composables manage reactive state, compute derived values, register lifecycle hooks, and synchronize external resources (like browser APIs, WebSockets, or network requests).

Composables solve the key limitations of Vue 2's code reuse patterns:
1. **Mixins**: Implicit property collisions, unclear source of properties, tight coupling.
2. **Scoped Slots / Renderless Components**: Component tree bloating, performance overhead, awkward syntax for non-UI logic.
3. **Higher-Order Components (HOCs)**: Complex prop forwarding and TypeScript typing difficulties.

In Vue 3, composables are the primary mechanism for abstracting business and UI logic.

---

## Composable Conventions and Best Practices

1. **Naming Convention**: Always prefix composable function names with `use` (e.g., `useFetch`, `useLocalStorage`, `useWindowSize`, `useAuth`).
2. **Input Flexibility with `toValue` / `MaybeRefOrGetter`**: Accept plain values, refs, or getter functions (`() => val`) to make the composable universally flexible.
3. **Return Format**: Always return a plain object containing multiple `ref`s (or `readonly(ref)`s). Do **not** return a `reactive()` object directly, because destructuring in the consuming component would strip reactivity.
4. **Lifecycle Scoping**: Call lifecycle hooks (`onMounted`, `onUnmounted`) inside the composable if resource setup and teardown are needed.
5. **SSR Compatibility**: Guard browser-only APIs (`window`, `document`, `navigator`, `localStorage`) by checking `typeof window !== 'undefined'`.

---

## Anatomy of a Production-Grade Composable

Let us build a comprehensive `useFetch` composable that handles abort controllers, automatic re-fetching on URL/parameter changes, error handling, caching, and manual execution.

```typescript
// src/composables/useFetch.ts
import { ref, shallowRef, isRef, watchEffect, toValue, type Ref, type MaybeRefOrGetter } from "vue";

export interface UseFetchOptions<T> {
  immediate?: boolean;
  initialData?: T;
  timeout?: number;
  headers?: MaybeRefOrGetter<Record<string, string>>;
  transform?: (raw: any) => T;
}

export interface UseFetchReturn<T> {
  data: Ref<T | null>;
  error: Ref<Error | null>;
  isLoading: Ref<boolean>;
  isFinished: Ref<boolean>;
  statusCode: Ref<number | null>;
  abort: () => void;
  execute: () => Promise<void>;
}

export function useFetch<T = unknown>(
  url: MaybeRefOrGetter<string>,
  options: UseFetchOptions<T> = {}
): UseFetchReturn<T> {
  const {
    immediate = true,
    initialData = null,
    timeout = 10000,
    headers,
    transform,
  } = options;

  const data = shallowRef<T | null>(initialData);
  const error = shallowRef<Error | null>(null);
  const isLoading = ref<boolean>(false);
  const isFinished = ref<boolean>(false);
  const statusCode = ref<number | null>(null);

  let currentController: AbortController | null = null;

  const abort = () => {
    if (currentController) {
      currentController.abort();
      currentController = null;
    }
  };

  const execute = async () => {
    // Cancel previous inflight request
    abort();

    const targetUrl = toValue(url);
    if (!targetUrl) return;

    currentController = new AbortController();
    const timeoutId = setTimeout(() => {
      if (currentController) {
        currentController.abort();
      }
    }, timeout);

    isLoading.value = true;
    isFinished.value = false;
    error.value = null;

    try {
      const resolvedHeaders = headers ? toValue(headers) : {};
      const response = await fetch(targetUrl, {
        signal: currentController.signal,
        headers: {
          "Content-Type": "application/json",
          ...resolvedHeaders,
        },
      });

      statusCode.value = response.status;

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const rawJson = await response.json();
      data.value = transform ? transform(rawJson) : rawJson;
    } catch (err: unknown) {
      if (err instanceof Error && err.name === "AbortError") {
        // Request was deliberately canceled
        return;
      }
      error.value = err instanceof Error ? err : new Error(String(err));
      data.value = null;
    } finally {
      clearTimeout(timeoutId);
      isLoading.value = false;
      isFinished.value = true;
    }
  };

  if (immediate) {
    // If url or headers are reactive getters/refs, watchEffect automatically triggers execute() on changes
    watchEffect(() => {
      execute();
    });
  }

  return {
    data,
    error,
    isLoading,
    isFinished,
    statusCode,
    abort,
    execute,
  };
}
```

---

## Browser API Composables: `useEventListener` & `useLocalStorage`

### 1. `useEventListener`

Attaches event listeners safely and automatically cleans them up when the component unmounts or when the target element changes.

```typescript
// src/composables/useEventListener.ts
import { onMounted, onUnmounted, isRef, watch, unref, type MaybeRef } from "vue";

export function useEventListener<K extends keyof WindowEventMap>(
  target: Window,
  event: K,
  listener: (this: Window, ev: WindowEventMap[K]) => any,
  options?: boolean | AddEventListenerOptions
): () => void;

export function useEventListener<K extends keyof DocumentEventMap>(
  target: Document,
  event: K,
  listener: (this: Document, ev: DocumentEventMap[K]) => any,
  options?: boolean | AddEventListenerOptions
): () => void;

export function useEventListener<K extends keyof HTMLElementEventMap>(
  target: MaybeRef<HTMLElement | null | undefined>,
  event: K,
  listener: (this: HTMLElement, ev: HTMLElementEventMap[K]) => any,
  options?: boolean | AddEventListenerOptions
): () => void;

export function useEventListener(
  target: any,
  event: string,
  listener: EventListenerOrEventListenerObject,
  options?: boolean | AddEventListenerOptions
) {
  let cleanup = () => {};

  const register = (el: any) => {
    cleanup();
    if (!el) return;
    el.addEventListener(event, listener, options);
    cleanup = () => el.removeEventListener(event, listener, options);
  };

  if (isRef(target)) {
    watch(target, (newEl) => register(newEl), { immediate: true });
  } else {
    onMounted(() => register(unref(target)));
  }

  onUnmounted(() => {
    cleanup();
  });

  return cleanup;
}
```

### 2. `useLocalStorage` with Reactive Synchronization

Synchronizes a reactive ref with browser `localStorage`, listening to cross-tab `storage` events.

```typescript
// src/composables/useLocalStorage.ts
import { ref, watch, type Ref } from "vue";
import { useEventListener } from "./useEventListener";

export function useLocalStorage<T>(
  key: string,
  initialValue: T
): Ref<T> {
  const readValue = (): T => {
    if (typeof window === "undefined") {
      return initialValue;
    }
    try {
      const raw = window.localStorage.getItem(key);
      return raw ? JSON.parse(raw) : initialValue;
    } catch (err) {
      console.warn(`[useLocalStorage] Error reading key "${key}":`, err);
      return initialValue;
    }
  };

  const state = ref<T>(readValue()) as Ref<T>;

  // Sync state mutations to LocalStorage
  watch(
    state,
    (val) => {
      if (typeof window === "undefined") return;
      try {
        if (val === null || val === undefined) {
          window.localStorage.removeItem(key);
        } else {
          window.localStorage.setItem(key, JSON.stringify(val));
        }
      } catch (err) {
        console.error(`[useLocalStorage] Error writing key "${key}":`, err);
      }
    },
    { deep: true }
  );

  // Sync cross-tab updates via window storage event
  if (typeof window !== "undefined") {
    useEventListener(window, "storage", (event: StorageEvent) => {
      if (event.key === key && event.newValue !== null) {
        try {
          state.value = JSON.parse(event.newValue);
        } catch {
          // ignore corrupted data
        }
      }
    });
  }

  return state;
}
```

---

## Composing Multiple Composables (Compound Architecture)

One of the greatest strengths of the Composition API is assembling small, focused composables into higher-level business features:

```typescript
// src/composables/useUserProfile.ts
import { computed } from "vue";
import { useFetch } from "./useFetch";
import { useLocalStorage } from "./useLocalStorage";

export interface UserProfile {
  id: string;
  name: string;
  role: "admin" | "editor" | "viewer";
  avatar: string;
}

export function useUserProfile() {
  const authToken = useLocalStorage<string | null>("auth_token", null);

  const authHeaders = computed(() => ({
    Authorization: authToken.value ? `Bearer ${authToken.value}` : "",
  }));

  const {
    data: profile,
    isLoading,
    error,
    execute: refreshProfile,
  } = useFetch<UserProfile>("/api/v1/user/me", {
    headers: authHeaders,
    immediate: computed(() => Boolean(authToken.value)),
  });

  const isAuthenticated = computed(() => Boolean(authToken.value && profile.value));
  const isAdmin = computed(() => profile.value?.role === "admin");

  const logout = () => {
    authToken.value = null;
    profile.value = null;
  };

  return {
    profile,
    isLoading,
    error,
    isAuthenticated,
    isAdmin,
    refreshProfile,
    logout,
  };
}
```

---

## Consuming Composables in Single File Components

```vue
<!-- src/views/DashboardView.vue -->
<script setup lang="ts">
import { ref } from "vue";
import { useUserProfile } from "@/composables/useUserProfile";
import { useEventListener } from "@/composables/useEventListener";

const { profile, isLoading, error, isAdmin, logout } = useUserProfile();
const mousePos = ref({ x: 0, y: 0 });

useEventListener(window, "mousemove", (e) => {
  mousePos.value = { x: e.clientX, y: e.clientY };
});
</script>

<template>
  <div class="dashboard">
    <div v-if="isLoading" class="loading-skeleton">
      Loading user profile...
    </div>

    <div v-else-if="error" class="error-banner">
      Failed to load profile: {{ error.message }}
    </div>

    <div v-else-if="profile" class="profile-card">
      <img :src="profile.avatar" :alt="profile.name" class="avatar" />
      <h2>{{ profile.name }}</h2>
      <span v-if="isAdmin" class="badge admin">System Administrator</span>
      <button @click="logout" class="btn-logout">Log Out</button>
    </div>

    <footer class="telemetry">
      Cursor Coordinates: X: {{ mousePos.x }}, Y: {{ mousePos.y }}
    </footer>
  </div>
</template>
```

---

## Troubleshooting & Anti-Patterns

**1. Destructuring a reactive object inside a composable**
```typescript
// ❌ WRONG: Destructuring strips proxy tracking
export function useCounter() {
  const state = reactive({ count: 0 });
  return { ...state }; // Returns plain { count: 0 }, not reactive!
}

// ✅ CORRECT: Return refs or use toRefs
export function useCounter() {
  const count = ref(0);
  return { count };
}
```

**2. Calling lifecycle hooks conditionally or outside synchronous setup**
```typescript
// ❌ WRONG: Calling onMounted inside an async callback
export function useBadAsync() {
  setTimeout(() => {
    onMounted(() => {}); // Error: onMounted() is called when there is no active component instance!
  }, 1000);
}

// ✅ CORRECT: Register lifecycle hooks synchronously in the composable body
export function useGoodAsync() {
  onMounted(() => {
    // Setup listeners or async work here
  });
}
```

**3. Memory leaks from missing cleanup**
Always ensure event listeners, timers, web workers, and websocket connections created inside a composable are registered with `onUnmounted()` or `onScopeDispose()`.
