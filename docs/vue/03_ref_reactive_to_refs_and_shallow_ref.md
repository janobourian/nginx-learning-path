# Module 03: `ref`, `reactive`, `toRefs` & `shallowRef`

**Track:** Vue — Progressive Web Framework  
**Category:** Reactivity API Mastery

---

## Choosing Between `ref` and `reactive`

The Vue team's recommendation for Vue 3:

> **Use `ref()` for everything by default.** `reactive()` has gotchas around destructuring and reassignment that `ref()` avoids. Use `reactive()` when you have a group of closely related state that always changes together and you want to use it as an object.

Understanding why this is the recommendation requires seeing both in action.

---

## `ref()` in Depth

`ref()` accepts any value — primitive or object — and returns a reactive wrapper with a single `.value` property.

```typescript
import { ref } from "vue";

// Primitives
const count = ref(0);
const name = ref("Alice");
const isOpen = ref(false);

// Objects — ref wraps in reactive internally for nested reactivity
const user = ref({
  id: crypto.randomUUID(),
  name: "Alice",
  roles: ["user", "editor"],
  preferences: {
    theme: "dark",
    language: "en",
  },
});

// Accessing ref values in <script>: always .value
count.value++;
name.value = "Bob";
user.value.name = "Bob";                    // Nested access, still reactive
user.value.preferences.theme = "light";    // Deep change, still reactive
user.value.roles.push("admin");             // Array mutation, still reactive

// Replacing the whole object: assign a new value to .value
user.value = {
  id: crypto.randomUUID(),
  name: "Carol",
  roles: ["admin"],
  preferences: { theme: "light", language: "fr" },
};
```

### `ref()` for DOM Element References

`ref()` is also used to hold references to DOM elements and child component instances:

```vue
<script setup lang="ts">
import { ref, onMounted } from "vue";

// Declare a ref to hold a DOM element
const inputEl = ref<HTMLInputElement | null>(null);
const canvasEl = ref<HTMLCanvasElement | null>(null);

onMounted(() => {
  // Elements are available after mounting
  inputEl.value?.focus();

  if (canvasEl.value) {
    const ctx = canvasEl.value.getContext("2d")!;
    ctx.fillStyle = "#42b883";
    ctx.fillRect(0, 0, 200, 100);
  }
});
</script>

<template>
  <!-- The ref attribute name must match the const name -->
  <input ref="inputEl" type="text" placeholder="Auto-focused" />
  <canvas ref="canvasEl" width="200" height="100" />
</template>
```

---

## `reactive()` in Depth

`reactive()` wraps an object (or array) in a Proxy and makes ALL nested properties reactive. Unlike `ref()`, it does not have a `.value` wrapper — you access properties directly.

```typescript
import { reactive } from "vue";

const formState = reactive({
  username: "",
  email: "",
  password: "",
  confirmPassword: "",
  agreedToTerms: false,
});

// Direct property access — no .value
formState.username = "alice";
formState.email = "alice@example.com";

// Works well for form state because all fields change together
// and you pass the whole formState object around
```

### The Destructuring Problem

This is the critical gotcha with `reactive()`:

```typescript
import { reactive } from "vue";

const state = reactive({ count: 0, name: "Alice" });

// ❌ WRONG: destructuring breaks reactivity
const { count, name } = state;
count;  // Now just a plain number — NOT reactive
name;   // Just a plain string — NOT reactive
// Template updates won't fire when count or name change

// ✅ CORRECT: always access via the reactive object
state.count++;
state.name = "Bob";

// ✅ CORRECT: if you need destructuring, use toRefs
import { toRefs } from "vue";
const { count: countRef, name: nameRef } = toRefs(state);
countRef.value++;  // Now reactive — linked back to state.count
```

---

## `toRefs()` — Bridge Between `reactive` and `ref`

`toRefs()` converts each property of a reactive object into a ref. The refs remain linked to the original reactive object — writing to the ref writes to the reactive object and vice versa.

```typescript
import { reactive, toRefs } from "vue";

const position = reactive({ x: 0, y: 0, z: 0 });

// Safe destructuring via toRefs
const { x, y, z } = toRefs(position);

x.value = 100;         // Same as position.x = 100
console.log(position.x); // 100

position.y = 200;
console.log(y.value);  // 200

// ── Most useful in composable functions ────────────────────────────────────
// Composables should return refs (not reactive objects) so callers can
// destructure the return value safely

function useMousePosition() {
  const pos = reactive({ x: 0, y: 0 });

  const onMouseMove = (event: MouseEvent) => {
    pos.x = event.clientX;
    pos.y = event.clientY;
  };

  onMounted(() => window.addEventListener("mousemove", onMouseMove));
  onUnmounted(() => window.removeEventListener("mousemove", onMouseMove));

  // Return toRefs so callers can destructure safely
  return toRefs(pos);
}

// In a component:
const { x, y } = useMousePosition();  // Both x and y are reactive refs
// vs. returning reactive(pos) which would lose reactivity if destructured
```

---

## `toRef()` — Single Property Ref

`toRef()` converts a single property of a reactive object to a ref:

```typescript
import { reactive, toRef } from "vue";

const user = reactive({ name: "Alice", age: 30, active: true });

// Only expose 'name' as a ref
const name = toRef(user, "name");
name.value = "Bob";       // Updates user.name
console.log(user.name);   // "Bob"

// Useful when passing one property to a child component or composable
// that expects a ref, without exposing the entire reactive object
```

---

## `shallowRef()` — Performance for Large Data

`shallowRef()` creates a ref where only the `.value` property itself is reactive. If `.value` is an object, mutations to its nested properties do NOT trigger updates:

```typescript
import { shallowRef, triggerRef } from "vue";

// Large table data — we always replace the whole dataset, never mutate rows
const tableData = shallowRef<Row[]>([]);

// ✅ Replacement triggers update (shallow tracking sees .value changed)
tableData.value = await fetchData();

// ❌ Mutation does NOT trigger update (shallowRef doesn't track inside .value)
tableData.value[0].name = "Alice";  // No re-render!

// ✅ If you MUST mutate and trigger:
tableData.value[0].name = "Alice";
triggerRef(tableData);  // Manually tell Vue to re-render

interface Row { id: number; name: string; }
```

Performance comparison for a component rendering a 10,000-row table:

- `ref(bigArray)` — Every render wraps each element in a Proxy. Slow.
- `shallowRef(bigArray)` — Only `.value` itself is wrapped. 10-100x faster.

---

## `shallowReactive()` — Shallow Object Reactivity

```typescript
import { shallowReactive, isReactive } from "vue";

const state = shallowReactive({
  name: "Alice",          // top-level — reactive
  address: {              // top-level ref is reactive...
    city: "New York",     // ...but nested is NOT reactive
    zip: "10001",
  },
});

state.name = "Bob";       // ✅ Triggers update
state.address = { city: "LA", zip: "90001" }; // ✅ Replacing the whole object triggers
state.address.city = "LA"; // ❌ Does NOT trigger update (nested not tracked)

console.log(isReactive(state));         // true
console.log(isReactive(state.address)); // false (nested is plain object)
```

---

## `readonly()` and `shallowReadonly()`

Create read-only versions of reactive data — useful for exposing store state without allowing direct mutation:

```typescript
import { reactive, readonly } from "vue";

const internalState = reactive({ count: 0 });
const publicState = readonly(internalState);

// Internal code can mutate
internalState.count++;

// External code gets read-only version
console.log(publicState.count); // 1
publicState.count++;  // ❌ TypeError: Cannot set property 'count' — it's readonly

// Changes to internalState ARE reflected in publicState (it's a view)
internalState.count = 10;
console.log(publicState.count); // 10
```

---

## Complete Example: Form State Management

```vue
<script setup lang="ts">
import { ref, reactive, computed, toRefs } from "vue";

interface FormFields {
  email: string;
  password: string;
  confirmPassword: string;
}

const fields = reactive<FormFields>({
  email: "",
  password: "",
  confirmPassword: "",
});

const errors = reactive<Partial<Record<keyof FormFields, string>>>({});
const isSubmitting = ref(false);

const isValid = computed(() => {
  return (
    fields.email.includes("@") &&
    fields.password.length >= 8 &&
    fields.password === fields.confirmPassword
  );
});

function validate(): boolean {
  errors.email = fields.email.includes("@") ? undefined : "Valid email required";
  errors.password = fields.password.length >= 8 ? undefined : "Min 8 characters";
  errors.confirmPassword =
    fields.password === fields.confirmPassword ? undefined : "Passwords do not match";
  return !Object.values(errors).some(Boolean);
}

async function submit() {
  if (!validate()) return;
  isSubmitting.value = true;
  try {
    await registerUser(fields);
  } finally {
    isSubmitting.value = false;
  }
}

async function registerUser(_fields: FormFields): Promise<void> {
  // API call
}

// Expose destructurable refs for the template
const { email, password, confirmPassword } = toRefs(fields);
</script>

<template>
  <form @submit.prevent="submit">
    <label>
      Email
      <input v-model="email" type="email" :class="{ error: errors.email }" />
      <span v-if="errors.email" class="error-msg">{{ errors.email }}</span>
    </label>

    <label>
      Password
      <input v-model="password" type="password" />
      <span v-if="errors.password" class="error-msg">{{ errors.password }}</span>
    </label>

    <label>
      Confirm Password
      <input v-model="confirmPassword" type="password" />
      <span v-if="errors.confirmPassword" class="error-msg">{{ errors.confirmPassword }}</span>
    </label>

    <button type="submit" :disabled="!isValid || isSubmitting">
      {{ isSubmitting ? "Registering..." : "Register" }}
    </button>
  </form>
</template>
```

---

## Troubleshooting

**`ref.value` is undefined inside a template expression**

The ref must be returned from `setup()` (Options API) or declared at the top level of `<script setup>`. Refs declared inside functions or conditionals inside `<script setup>` are not accessible in the template.

**Mutating a `reactive` object's nested array doesn't trigger updates**

It should. `reactive()` wraps all nested objects and arrays in proxies. If mutations are not triggering updates, the array may have been replaced with a non-reactive version somewhere. Use `console.log(isReactive(state.myArray))` to verify.

**`triggerRef` doesn't seem to cause an update**

Ensure you're calling `triggerRef(myRef)`, not `triggerRef(myRef.value)`. Also verify that the template is actually reading `.value` (or the unwrapped ref) — if the template never reads the ref, there's no subscriber to notify.
