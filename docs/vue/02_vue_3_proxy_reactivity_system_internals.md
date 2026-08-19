# Module 02: Vue 3 Proxy Reactivity System — Internals

**Track:** Vue — Progressive Web Framework
**Category:** Reactivity System & Framework Internals

---

## How Vue's Reactivity System Works

Vue 3's reactivity is built on JavaScript `Proxy` objects. Understanding the internals helps you write more efficient components, diagnose subtle bugs, and reason about when and why the DOM updates.

At its core, Vue's reactivity does three things:

1. **Track**: when a reactive value is read, record which effect (computed, watch, render) is currently running
2. **Trigger**: when a reactive value is written, notify all effects that read it to re-run
3. **Update**: effects that are component render functions schedule a DOM update in the next microtask

---

## The `Proxy`-Based Foundation

Vue 2 used `Object.defineProperty()` to intercept property reads and writes. This had limitations: it couldn't detect property additions or deletions, and arrays required special handling.

Vue 3 uses `Proxy`, which wraps the entire object and intercepts any property operation on it:

```typescript
// Simplified version of Vue's reactive() — what the framework does internally
function createReactive<T extends object>(target: T): T {
  return new Proxy(target, {
    // Called when any property is READ
    get(target, key, receiver) {
      // Track: record that the current active effect depends on this property
      track(target, key);
      const value = Reflect.get(target, key, receiver);
      // Nested objects: recursively make them reactive too
      if (typeof value === "object" && value !== null) {
        return createReactive(value);
      }
      return value;
    },

    // Called when any property is WRITTEN
    set(target, key, value, receiver) {
      const oldValue = target[key as keyof T];
      const result = Reflect.set(target, key, value, receiver);
      if (value !== oldValue) {
        // Trigger: notify all effects that depend on this property to re-run
        trigger(target, key);
      }
      return result;
    },

    // Called when a property is DELETED (not possible in Vue 2)
    deleteProperty(target, key) {
      const result = Reflect.deleteProperty(target, key);
      trigger(target, key);
      return result;
    },
  });
}

// The actual track/trigger are Vue internal functions — simplified here
const activeEffect: (() => void) | null = null;
const targetMap = new WeakMap<object, Map<PropertyKey, Set<() => void>>>();

function track(target: object, key: PropertyKey) {
  if (!activeEffect) return;
  let depsMap = targetMap.get(target);
  if (!depsMap) targetMap.set(target, (depsMap = new Map()));
  let dep = depsMap.get(key);
  if (!dep) depsMap.set(key, (dep = new Set()));
  dep.add(activeEffect);
}

function trigger(target: object, key: PropertyKey) {
  const depsMap = targetMap.get(target);
  if (!depsMap) return;
  const effects = depsMap.get(key);
  effects?.forEach((effect) => effect());
}
```

This is why Vue's reactivity is **automatic**: you don't manually subscribe or unsubscribe. When a component renders, its render function reads reactive values — Vue records those reads. When you write to a reactive value, Vue knows exactly which components to re-render.

---

## `reactive()` — Deep Object Reactivity

`reactive()` creates a Proxy around an object. All nested properties are also reactive.

```typescript
import { reactive, isReactive, toRaw } from "vue";

const state = reactive({
  user: {
    name: "Alice",
    address: {
      city: "New York",
      zip: "10001",
    },
  },
  todos: [
    { id: 1, text: "Buy groceries", done: false },
    { id: 2, text: "Write tests", done: true },
  ],
});

// Reading a property tracks it
console.log(state.user.name);         // "Alice"
console.log(state.user.address.city); // "New York" — nested object is also reactive

// Mutations trigger updates
state.user.name = "Bob";              // Triggers re-render of anything using user.name
state.todos.push({ id: 3, text: "Deploy", done: false }); // Array mutation is tracked

// isReactive: check if a value is a reactive proxy
console.log(isReactive(state));           // true
console.log(isReactive(state.user));      // true (nested objects are reactive)
console.log(isReactive(state.user.name)); // false (primitives are not objects)

// toRaw: get the underlying plain object (bypasses the proxy)
const plainState = toRaw(state);
console.log(isReactive(plainState)); // false
```

### Limitations of `reactive()`

```typescript
const state = reactive({ count: 0 });

// ❌ LOSES reactivity: destructuring breaks the proxy connection
const { count } = state;
count; // This is now a plain number, not reactive

// ❌ LOSES reactivity: replacing the reactive object entirely
let state2 = reactive({ count: 0 });
state2 = reactive({ count: 1 }); // state2 variable now points to a new proxy; old consumers lose it

// ✅ CORRECT: keep references through the proxy
state.count++;  // Modifying via the proxy
```

---

## `ref()` — Reactive Primitive Values

`reactive()` only works on objects. For primitives (strings, numbers, booleans), use `ref()`. A ref wraps the value in a reactive object with a single `.value` property:

```typescript
import { ref, isRef, unref } from "vue";

const count = ref(0);      // Wraps 0 in { value: 0 }
const name = ref("Alice"); // Wraps "Alice" in { value: "Alice" }
const user = ref({ id: 1, name: "Alice" }); // Object: ref wraps, reactive applies inside

// Reading and writing always via .value in script
console.log(count.value);  // 0
count.value++;             // Triggers reactivity
count.value = 42;

// In templates: .value is automatically unwrapped — no need to write count.value
// <p>{{ count }}</p>  ← Works directly

// isRef: check if a value is a ref
console.log(isRef(count));    // true
console.log(isRef(0));        // false

// unref: if it's a ref, return .value; otherwise return the value itself
// Useful for functions that accept both refs and plain values
function useValue(val: number | Ref<number>): number {
  return unref(val);  // Returns val.value if ref, or val directly
}
```

### Ref Automatic Unwrapping

When a `ref` is accessed as a property of a `reactive` object, it is automatically unwrapped (you access its value directly without `.value`):

```typescript
import { reactive, ref } from "vue";

const count = ref(0);
const state = reactive({ count }); // ref is nested inside reactive

// Automatic unwrapping in reactive:
console.log(state.count);     // 0 (not state.count.value)
state.count++;                // Works directly
console.log(state.count);     // 1

// BUT in a plain array, refs are NOT unwrapped:
const arr = reactive([ref(0)]);
console.log(arr[0].value);    // Must use .value here
```

In templates, **all top-level refs are auto-unwrapped**:

```vue
<script setup>
const count = ref(0);
const user = ref({ name: "Alice" });
</script>
<template>
  <!-- No .value needed in templates -->
  <p>{{ count }}</p>
  <p>{{ user.name }}</p>
</template>
```

---

## `computed()` — Derived Reactive Values

`computed()` creates a reactive value derived from other reactive values. It **caches** the result — the getter only re-runs when a dependency changes:

```typescript
import { ref, computed } from "vue";

const firstName = ref("Alice");
const lastName = ref("Chen");
const items = ref([
  { name: "Apple", price: 1.99, quantity: 3 },
  { name: "Banana", price: 0.99, quantity: 5 },
]);

// Read-only computed
const fullName = computed(() => `${firstName.value} ${lastName.value}`);

console.log(fullName.value); // "Alice Chen"
firstName.value = "Bob";
console.log(fullName.value); // "Bob Chen" — recomputed because firstName changed

// Computed is cached — getter does NOT re-run on repeated reads if deps unchanged
console.log(fullName.value); // "Bob Chen" — from cache, getter NOT called again

// Writable computed (get + set)
const fullNameWritable = computed({
  get: () => `${firstName.value} ${lastName.value}`,
  set: (newValue: string) => {
    const [first, last] = newValue.split(" ");
    firstName.value = first;
    lastName.value = last ?? "";
  },
});

fullNameWritable.value = "Carol White";
console.log(firstName.value); // "Carol"
console.log(lastName.value);  // "White"

// Complex computed: total price
const totalPrice = computed(() =>
  items.value.reduce((sum, item) => sum + item.price * item.quantity, 0)
);

// Filtered list
const expensiveItems = computed(() =>
  items.value.filter((item) => item.price > 1.50)
);
```

---

## The Effect System: `watchEffect()` and `watch()`

Both `watchEffect` and `watch` are Vue effects — functions that run reactively when their dependencies change.

```typescript
import { ref, computed, watchEffect, watch } from "vue";

const count = ref(0);
const doubled = computed(() => count.value * 2);

// watchEffect: runs immediately, auto-tracks all reactive reads
const stop = watchEffect(() => {
  // Dependencies (count.value, doubled.value) are tracked automatically
  console.log(`Count is ${count.value}, doubled is ${doubled.value}`);
});

count.value = 5; // Logs: "Count is 5, doubled is 10"
count.value = 10; // Logs: "Count is 10, doubled is 20"

// Stop the effect manually
stop(); // No more logging

// watch: explicit source(s), runs ONLY when those change
watch(count, (newValue, oldValue) => {
  console.log(`count changed from ${oldValue} to ${newValue}`);
});

// Watch multiple sources
watch([count, doubled], ([newCount, newDoubled], [oldCount, oldDoubled]) => {
  console.log({ newCount, newDoubled, oldCount, oldDoubled });
});

// Watch with options
watch(count, (newVal) => {
  console.log("count:", newVal);
}, {
  immediate: true,   // Run immediately (like watchEffect)
  deep: true,        // Deep watch nested objects
  once: true,        // Fire only once
  flush: "post",     // Run AFTER DOM updates (default: "pre")
});
```

---

## `shallowRef()` and `shallowReactive()` — Performance Optimization

For large objects that you always replace rather than mutate in place, shallow variants avoid the overhead of deep proxy wrapping:

```typescript
import { shallowRef, shallowReactive, triggerRef } from "vue";

// shallowRef: only .value itself is reactive; nested properties are NOT
const bigList = shallowRef<Item[]>([]);

// Correct: replace the array (triggers reactivity)
bigList.value = [...bigList.value, newItem];

// Wrong: mutating .value's contents does NOT trigger reactivity
bigList.value.push(newItem); // No update triggered!

// Manual trigger if you need to mutate and then trigger:
bigList.value.push(newItem);
triggerRef(bigList); // Force trigger

// shallowReactive: top-level properties are reactive, nested are NOT
const tableState = shallowReactive({
  rows: [] as Row[],          // Replacing rows triggers reactivity
  selectedIds: new Set<number>(),
  config: { pageSize: 20 },  // Mutations to config.pageSize do NOT trigger updates
});

interface Item { id: number; name: string; }
interface Row { cells: string[]; }
```

---

## Troubleshooting

### Template doesn't update when I push to an array

If the array is inside a `reactive` object, push IS tracked (`state.items.push(...)` works). If the array itself is a top-level `ref`, use `items.value.push(...)`. If you used `shallowRef`, you must replace the array or call `triggerRef`.

### `computed` value isn't updating

The getter must directly access the reactive value inside the getter function. If you read a reactive value *before* the `computed(() => ...)` call and pass it as a variable, the computed doesn't track it. Always access reactive values (`ref.value`, `reactive.property`) inside the getter body.

### Two components share the same `reactive` object but changes in one don't appear in the other

This is the expected behavior if they each call `reactive({})` with a fresh object. Share reactive state by exporting the same reactive object from a module or a Pinia store.
