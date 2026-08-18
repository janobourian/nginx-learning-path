# Module 05: Watchers — `watch`, `watchEffect` & Lifecycle Hooks

**Track:** Vue — Progressive Web Framework  
**Category:** Side Effects & Component Lifecycle

---

## When to Use Watchers vs Computed

| Scenario | Use |
|---|---|
| Derive a value from other state | `computed()` |
| React to state changes with a side effect (API call, logging, DOM manipulation) | `watch()` or `watchEffect()` |
| Run setup code when a component mounts | `onMounted()` |
| Clean up timers, subscriptions, listeners | `onUnmounted()` |

---

## `watchEffect()` — Auto-Tracked Side Effects

`watchEffect()` runs a function immediately, tracking all reactive dependencies it reads. When any dependency changes, it re-runs the function.

```typescript
import { ref, watchEffect, onUnmounted } from "vue";

const userId = ref("user-1");
const userData = ref<{ name: string; email: string } | null>(null);
const error = ref<string | null>(null);
const isLoading = ref(false);

// Auto-tracks: reads userId.value → re-runs when userId changes
const stop = watchEffect(async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const response = await fetch(`/api/users/${userId.value}`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    userData.value = await response.json();
  } catch (e) {
    error.value = e instanceof Error ? e.message : "Unknown error";
    userData.value = null;
  } finally {
    isLoading.value = false;
  }
});

// Manual stop (also stopped automatically when component unmounts)
// stop();

// Cleanup function: runs before the effect re-runs or when the component unmounts
watchEffect((onCleanup) => {
  const controller = new AbortController();
  const { signal } = controller;

  fetch(`/api/data/${userId.value}`, { signal })
    .then((r) => r.json())
    .then((data) => { userData.value = data; });

  // Cleanup: cancel the previous request when userId changes
  onCleanup(() => controller.abort());
});
```

---

## `watch()` — Explicit Source Watching

`watch()` is more explicit: you specify exactly what to watch, and the callback only runs when that specific source changes (not on mount, unlike `watchEffect`).

```typescript
import { ref, computed, watch } from "vue";

const count = ref(0);
const user = ref({ name: "Alice", role: "user" });
const searchQuery = ref("");
const results = ref<string[]>([]);

// Watch a single ref
watch(count, (newValue, oldValue) => {
  console.log(`count: ${oldValue} → ${newValue}`);
});

// Watch a reactive object's property using a getter function
watch(
  () => user.value.role,
  (newRole, oldRole) => {
    if (newRole === "admin") {
      loadAdminFeatures();
    }
  }
);

// Watch multiple sources simultaneously
watch(
  [count, () => user.value.name],
  ([newCount, newName], [oldCount, oldName]) => {
    console.log({ newCount, newName, oldCount, oldName });
  }
);

// Debounce: watch searchQuery and delay the API call
let debounceTimer: ReturnType<typeof setTimeout> | null = null;
watch(searchQuery, async (query) => {
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(async () => {
    if (!query.trim()) {
      results.value = [];
      return;
    }
    const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
    results.value = await response.json();
  }, 300);
});

// Watch with options
watch(count, (newVal) => {
  console.log("initial or changed:", newVal);
}, {
  immediate: true,    // Run immediately on setup (like watchEffect)
  deep: true,         // Deep watch nested objects (expensive — avoid on large objects)
  once: true,         // Run the handler only once, then auto-stop
  flush: "post",      // Run AFTER the DOM has been updated
});

function loadAdminFeatures() { /* ... */ }
```

### `flush` Option

The `flush` option controls when the watcher callback runs relative to DOM updates:

- `"pre"` (default) — runs before Vue updates the DOM. This means you can read old DOM state.
- `"post"` — runs after Vue has updated the DOM. Use when you need to access the updated DOM.
- `"sync"` — runs synchronously as soon as the dependency changes. Rarely needed, can cause cascading updates.

```typescript
import { ref, watch, nextTick } from "vue";

const count = ref(0);
const el = ref<HTMLDivElement | null>(null);

// You need to see the UPDATED DOM text content
watch(count, async () => {
  // With flush: "post", el.value.textContent already reflects the new count
  console.log("DOM text:", el.value?.textContent);
}, { flush: "post" });

// Alternative: use nextTick inside a "pre" watcher
watch(count, async () => {
  await nextTick(); // Wait for DOM update
  console.log("DOM text after nextTick:", el.value?.textContent);
});
```

---

## Deep Watching

```typescript
import { ref, reactive, watch } from "vue";

const userProfile = ref({
  name: "Alice",
  preferences: {
    theme: "dark",
    notifications: {
      email: true,
      sms: false,
    },
  },
});

// ❌ Default: shallow watch — only fires if the ref VALUE itself is replaced
watch(userProfile, (newVal) => {
  console.log("Profile changed:", newVal);
});
userProfile.value.preferences.theme = "light"; // Does NOT fire!

// ✅ Deep watch: fires for any nested change
watch(userProfile, (newVal) => {
  console.log("Profile changed:", newVal);
}, { deep: true });
userProfile.value.preferences.theme = "light"; // Fires ✓

// ✅ Better alternative: watch a specific nested getter (no deep needed)
watch(
  () => userProfile.value.preferences.theme,
  (newTheme) => {
    document.body.setAttribute("data-theme", newTheme);
  }
);
```

---

## Lifecycle Hooks

Vue 3 lifecycle hooks are functions you call inside `<script setup>`. They run in a specific order as the component moves through its lifecycle:

```
Creation:
  setup() / <script setup>
    → onBeforeMount()
    → [DOM rendered and inserted]
    → onMounted()

Updates (when reactive deps change):
    → onBeforeUpdate()
    → [DOM re-rendered]
    → onUpdated()

Destruction:
    → onBeforeUnmount()
    → [DOM removed]
    → onUnmounted()

Error Handling:
    → onErrorCaptured() — errors from child components

Keep-Alive:
    → onActivated()   — component re-enters keep-alive cache
    → onDeactivated() — component leaves the screen
```

```vue
<script setup lang="ts">
import {
  ref,
  onBeforeMount,
  onMounted,
  onBeforeUpdate,
  onUpdated,
  onBeforeUnmount,
  onUnmounted,
  onErrorCaptured,
  nextTick,
} from "vue";

const count = ref(0);
const el = ref<HTMLDivElement | null>(null);
let pollingInterval: ReturnType<typeof setInterval>;

// Runs before first render — DOM does not exist yet
onBeforeMount(() => {
  console.log("About to mount — el.value is:", el.value); // null
});

// Runs after first render — DOM exists and refs are available
onMounted(async () => {
  console.log("Mounted — el.value:", el.value); // <div>...</div>

  // Start a polling interval
  pollingInterval = setInterval(async () => {
    const response = await fetch("/api/status");
    // update state...
  }, 5000);

  // Access the DOM directly
  el.value?.focus();
});

// Runs before every re-render (when reactive data changes)
onBeforeUpdate(() => {
  // Read old DOM values before Vue updates them
});

// Runs after every re-render
onUpdated(async () => {
  // Read new DOM values after Vue has updated them
  // For async updates within the same tick, use nextTick
  await nextTick();
  console.log("Updated DOM:", el.value?.textContent);
});

// Runs before the component is removed from the DOM
onBeforeUnmount(() => {
  clearInterval(pollingInterval);  // Clean up the polling interval
});

// Runs after the component is removed
onUnmounted(() => {
  console.log("Component destroyed");
});

// Catches errors from descendant components
onErrorCaptured((error, instance, info) => {
  console.error("Caught error:", error, "in:", info);
  // Return false to prevent the error from propagating further
  return false;
});
</script>

<template>
  <div ref="el">Count: {{ count }}</div>
  <button @click="count++">Increment</button>
</template>
```

---

## `nextTick()` — Waiting for DOM Updates

Vue batches DOM updates asynchronously (as microtasks). After changing reactive state, the DOM is not immediately updated. Use `nextTick()` to wait:

```typescript
import { ref, nextTick } from "vue";

const message = ref("Hello");
const messageEl = ref<HTMLParagraphElement | null>(null);

async function updateMessage() {
  message.value = "Updated!";

  // DOM is NOT yet updated here
  console.log(messageEl.value?.textContent); // "Hello" (stale)

  await nextTick(); // Wait for Vue to flush the DOM update queue

  // DOM IS updated now
  console.log(messageEl.value?.textContent); // "Updated!"
}
```

---

## Troubleshooting

**`watchEffect` doesn't re-run when a reactive value changes**

The reactive value must be read synchronously inside the `watchEffect` callback. Reads inside async callbacks after the first `await` are NOT tracked (because the tracking context is lost across await boundaries). Access all reactive dependencies before the first `await`.

**`watch` fires on component mount even without `immediate: true`**

A `watch` with `{ deep: true }` on a reactive object may fire once at setup if the object is freshly created and Vue does an initial traversal. Remove `deep: true` and use a getter function (`() => obj.specificProp`) if you only need to watch specific properties.

**Cleanup function in `watchEffect` not running**

The cleanup function is called via the `onCleanup` parameter, not via a return value. Pattern: `watchEffect((onCleanup) => { ...; onCleanup(() => cleanup()); })`. Returning a function from `watchEffect` does NOT register it as cleanup.
