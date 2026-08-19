# Module 04: Computed Properties & Cached Getters

**Track:** Vue — Progressive Web Framework
**Category:** Derived State & Performance

---

## What `computed()` Does

A computed property is a reactive value derived from other reactive state. It behaves like a `ref` — you access it with `.value` in script, unwrapped in templates — but with one crucial characteristic: it **caches its result**.

The getter function only re-runs when one of its reactive dependencies changes. If you read the computed value 1,000 times without any dependency changing, the getter runs exactly once and the cached result is returned for the other 999 reads.

This is the fundamental performance advantage over methods: a method re-executes every time the template re-renders. A computed property re-executes only when its dependencies change.

---

## Read-Only Computed

```typescript
import { ref, computed } from "vue";

const items = ref([
  { id: 1, name: "Laptop", price: 1299.99, category: "electronics", inStock: true },
  { id: 2, name: "Phone", price: 799.99, category: "electronics", inStock: false },
  { id: 3, name: "Desk", price: 349.99, category: "furniture", inStock: true },
  { id: 4, name: "Chair", price: 249.99, category: "furniture", inStock: true },
  { id: 5, name: "Monitor", price: 599.99, category: "electronics", inStock: true },
]);

const searchQuery = ref("");
const selectedCategory = ref<string | null>(null);
const sortBy = ref<"name" | "price">("name");
const sortDirection = ref<"asc" | "desc">("asc");

// Filtered list: re-runs only when items, searchQuery, or selectedCategory changes
const filteredItems = computed(() => {
  let result = items.value;

  if (searchQuery.value.trim()) {
    const query = searchQuery.value.toLowerCase();
    result = result.filter(
      (item) =>
        item.name.toLowerCase().includes(query) ||
        item.category.toLowerCase().includes(query)
    );
  }

  if (selectedCategory.value) {
    result = result.filter((item) => item.category === selectedCategory.value);
  }

  return result;
});

// Sorted list: depends on filteredItems — cascaded computation
const sortedItems = computed(() => {
  return [...filteredItems.value].sort((a, b) => {
    const dir = sortDirection.value === "asc" ? 1 : -1;
    if (sortBy.value === "name") {
      return a.name.localeCompare(b.name) * dir;
    } else {
      return (a.price - b.price) * dir;
    }
  });
});

// Summary stats: re-runs only when items change
const stats = computed(() => ({
  total: items.value.length,
  inStock: items.value.filter((i) => i.inStock).length,
  outOfStock: items.value.filter((i) => !i.inStock).length,
  avgPrice: items.value.reduce((sum, i) => sum + i.price, 0) / items.value.length,
  maxPrice: Math.max(...items.value.map((i) => i.price)),
}));

// Category list: unique categories
const categories = computed(() =>
  [...new Set(items.value.map((i) => i.category))].sort()
);
```

---

## Writable Computed — Getter and Setter

```typescript
import { ref, computed } from "vue";

const firstName = ref("Alice");
const lastName = ref("Chen");

// Writable computed: reads derive from both, writes decompose
const fullName = computed({
  get: () => `${firstName.value} ${lastName.value}`,
  set: (value: string) => {
    const parts = value.trim().split(/\s+/);
    firstName.value = parts[0] ?? "";
    lastName.value = parts.slice(1).join(" ");
  },
});

console.log(fullName.value); // "Alice Chen"
fullName.value = "Bob Smith Johnson"; // Sets firstName = "Bob", lastName = "Smith Johnson"
console.log(firstName.value); // "Bob"
console.log(lastName.value);  // "Smith Johnson"
```

Another practical example — a temperature converter:

```typescript
const celsius = ref(0);

const fahrenheit = computed({
  get: () => (celsius.value * 9) / 5 + 32,
  set: (f: number) => {
    celsius.value = ((f - 32) * 5) / 9;
  },
});

console.log(fahrenheit.value); // 32
fahrenheit.value = 212;
console.log(celsius.value);    // 100
```

---

## Computed vs Method: The Performance Difference

```vue
<script setup lang="ts">
import { ref, computed } from "vue";

const list = ref<{ id: number; value: number }[]>(
  Array.from({ length: 10_000 }, (_, i) => ({ id: i, value: Math.random() }))
);

// ── Using a method: RE-RUNS on every component re-render ──────────────────
function sumAll_method() {
  console.log("method: sum computed");
  return list.value.reduce((sum, item) => sum + item.value, 0);
}

// ── Using computed: CACHED; only re-runs when list changes ─────────────────
const sumAll_computed = computed(() => {
  console.log("computed: sum computed");
  return list.value.reduce((sum, item) => sum + item.value, 0);
});

// If something ELSE changes (e.g., a UI toggle), the component re-renders.
// The method re-runs sumAll over 10,000 items — every re-render.
// The computed returns its cached value — no recomputation.
</script>

<template>
  <!-- In both cases, the template expression looks the same -->
  <p>Method sum: {{ sumAll_method() }}</p>
  <p>Computed sum: {{ sumAll_computed }}</p>
  <!-- NOTE: method is called with () — computed is accessed as a property -->
</template>
```

**Rule of thumb**: if a value involves any computation, use `computed`. Only use a method in the template if the method has a side effect (like opening a modal on click) or requires arguments (like `getItemById(id)` inside a `v-for`).

---

## Computed with Complex Objects and TypeScript

```typescript
import { ref, computed, type ComputedRef } from "vue";

interface User {
  id: string;
  name: string;
  email: string;
  role: "admin" | "editor" | "viewer";
  active: boolean;
  lastSeen: Date;
}

const users = ref<User[]>([]);
const currentUserId = ref<string | null>(null);

// TypeScript infers the return type automatically
const currentUser: ComputedRef<User | undefined> = computed(
  () => users.value.find((u) => u.id === currentUserId.value)
);

const isAdmin = computed(() => currentUser.value?.role === "admin");

const activeUsers = computed(() => users.value.filter((u) => u.active));

const usersByRole = computed(() => {
  const grouped = new Map<User["role"], User[]>();
  for (const user of users.value) {
    if (!grouped.has(user.role)) grouped.set(user.role, []);
    grouped.get(user.role)!.push(user);
  }
  return grouped;
});

// Computed that returns a function (factory pattern)
// Note: the function itself is NOT cached per call; only the computed wrapper is
const getUserById = computed(
  () => (id: string) => users.value.find((u) => u.id === id)
);

// Usage: getUserById.value("user-123")
```

---

## Avoiding Side Effects in Computed Getters

A computed getter must be a **pure function**: given the same reactive dependencies, it always returns the same result. It must NOT:

```typescript
import { ref, computed } from "vue";

const items = ref<string[]>([]);

// ❌ WRONG: Side effect in computed getter
const processedItems = computed(() => {
  console.log("Computing...");      // ❌ Side effect (logging)
  items.value.push("extra");        // ❌ Mutating state — causes infinite loop!
  return items.value.map((i) => i.toUpperCase());
});

// ✅ CORRECT: Pure transformation
const uppercasedItems = computed(() =>
  items.value.map((i) => i.toUpperCase())
);

// For side effects based on reactive data, use watch instead:
import { watch } from "vue";
watch(items, (newItems) => {
  console.log("Items changed:", newItems); // Side effect in watch is correct
});
```

---

## `computedAsync` — Async Computed (VueUse)

The built-in `computed()` is synchronous. For async computations (API calls), use `computedAsync` from VueUse or handle with `watchEffect`:

```typescript
// Using watchEffect for async derived state
import { ref, watchEffect } from "vue";

const userId = ref("user-123");
const userProfile = ref<{ name: string; email: string } | null>(null);
const isLoadingProfile = ref(false);

watchEffect(async () => {
  if (!userId.value) {
    userProfile.value = null;
    return;
  }
  isLoadingProfile.value = true;
  try {
    const response = await fetch(`/api/users/${userId.value}`);
    userProfile.value = await response.json();
  } finally {
    isLoadingProfile.value = false;
  }
});
// When userId.value changes, watchEffect re-runs the async function
```

---

## Troubleshooting

### Computed value is not updating when I expect it to

Log the dependencies: add `console.log` inside the getter to verify it re-runs. Then check whether the dependency is actually reactive. If you read a non-reactive variable (e.g., a plain array you didn't wrap in `ref()`), changes to it won't trigger the computed.

### Computed getter runs on every render even with no dependency changes

You may be creating a new object or array inside the getter that Vue sees as a new value on every read. Ensure dependencies are stable reactive refs. Also check for accidental reads of `Date.now()` or `Math.random()` inside the getter — these are not reactive dependencies and don't trigger re-computation, but they DO make every returned value different, causing downstream effects to always see "change".

### Writable computed setter isn't being called

Ensure you assigned to `computed.value = newValue`. If you wrote `computed = newValue` (without `.value`), you replaced the ref variable itself, not the ref's value.
