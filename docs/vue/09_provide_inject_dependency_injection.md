# Module 09: `provide` / `inject` — Dependency Injection

**Track:** Vue — Progressive Web Framework
**Category:** Cross-Component Communication

---

## The Problem Provide/Inject Solves

Props are the correct way to pass data one level down. But when data needs to travel many levels through the component tree — a pattern called **prop drilling** — every intermediate component must accept and pass along props it doesn't actually use:

```text
AppRoot (has user data)
  └── AppLayout (passes user prop, doesn't use it)
        └── Sidebar (passes user prop, doesn't use it)
              └── UserMenu (actually needs user data)
```

`provide` and `inject` create a direct tunnel from an ancestor to any descendant, regardless of depth:

```text
AppRoot → provide("user", userData)
                ↓ (any descendant)
UserMenu → inject("user")
```

---

## Basic `provide` and `inject`

```vue
<!-- AppRoot.vue — providing data to the entire app -->
<script setup lang="ts">
import { ref, provide, readonly } from "vue";

interface User {
  id: string;
  name: string;
  email: string;
  role: "admin" | "user";
}

const currentUser = ref<User | null>(null);
const isAuthenticated = ref(false);

async function loadUser() {
  const response = await fetch("/api/me");
  currentUser.value = await response.json();
  isAuthenticated.value = true;
}

await loadUser();

// Provide the data — uses a string key (or Symbol for uniqueness)
// Wrap in readonly so descendants cannot accidentally mutate it
provide("currentUser", readonly(currentUser));
provide("isAuthenticated", readonly(isAuthenticated));
</script>
```

```vue
<!-- Deep descendant: UserMenu.vue -->
<script setup lang="ts">
import { inject, computed, type Ref } from "vue";

// Inject the provided value — type annotation is required (Vue can't infer it)
const currentUser = inject<Ref<{ id: string; name: string; role: string } | null>>("currentUser");
const isAuthenticated = inject<Ref<boolean>>("isAuthenticated");

// Provide a fallback value for when inject is used outside the providing tree
const theme = inject<string>("theme", "light"); // "light" is the default

const displayName = computed(() =>
  currentUser?.value?.name ?? "Guest"
);
</script>

<template>
  <div v-if="isAuthenticated?.value" class="user-menu">
    <span>{{ displayName }}</span>
    <span v-if="currentUser?.value?.role === 'admin'" class="admin-badge">Admin</span>
  </div>
</template>
```

---

## Typed Injection Keys with Symbols

Using string keys for provide/inject is fragile — typos silently produce `undefined`. The recommended pattern is **injection key Symbols** with TypeScript types:

```typescript
// injection-keys.ts — share this between provider and consumer
import { type InjectionKey, type Ref } from "vue";

interface User {
  id: string;
  name: string;
  email: string;
  role: "admin" | "editor" | "viewer";
}

interface Theme {
  mode: "light" | "dark";
  primaryColor: string;
}

// Symbols guarantee uniqueness even if the name collides
export const UserKey: InjectionKey<Ref<User | null>> = Symbol("currentUser");
export const ThemeKey: InjectionKey<Ref<Theme>> = Symbol("theme");
export const AuthKey: InjectionKey<{
  isAuthenticated: Ref<boolean>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}> = Symbol("auth");
```

```vue
<!-- Provider: uses Symbol key -->
<script setup lang="ts">
import { ref, provide, readonly } from "vue";
import { UserKey, ThemeKey, AuthKey } from "@/injection-keys";

const user = ref<User | null>(null);
const theme = ref<Theme>({ mode: "dark", primaryColor: "#42b883" });

provide(UserKey, readonly(user));
provide(ThemeKey, theme);  // Allow descendants to modify theme
provide(AuthKey, {
  isAuthenticated: readonly(isAuthenticated),
  login: async (email, password) => { /* ... */ },
  logout: async () => { /* ... */ },
});
</script>
```

```vue
<!-- Consumer: type-safe injection without string keys -->
<script setup lang="ts">
import { inject } from "vue";
import { UserKey, ThemeKey, AuthKey } from "@/injection-keys";

// TypeScript knows the exact type — no casting needed
const user = inject(UserKey); // Ref<User | null> | undefined
const theme = inject(ThemeKey); // Ref<Theme> | undefined
const auth = inject(AuthKey);

// If the value is required and should always be provided:
const requiredTheme = inject(ThemeKey)!;  // Assert non-null
// Or with a guard:
if (!auth) throw new Error("AuthKey not provided — ensure AuthProvider wraps this component");
</script>
```

---

## Providing Functions for Two-Way Communication

Since `readonly` prevents descendants from mutating provided data, provide mutation functions alongside the data:

```vue
<!-- ThemeProvider.vue -->
<script setup lang="ts">
import { ref, provide, readonly } from "vue";
import { ThemeKey } from "@/injection-keys";

const theme = ref({ mode: "light" as "light" | "dark", primaryColor: "#42b883" });

function toggleTheme() {
  theme.value.mode = theme.value.mode === "light" ? "dark" : "light";
}

function setPrimaryColor(color: string) {
  theme.value.primaryColor = color;
}

// Provide both data and mutation functions
provide(ThemeKey, {
  theme: readonly(theme),
  toggleTheme,
  setPrimaryColor,
});
</script>

<template>
  <slot />
</template>
```

```vue
<!-- Any descendant: ThemeToggle.vue -->
<script setup lang="ts">
import { inject } from "vue";
import { ThemeKey } from "@/injection-keys";

const themeContext = inject(ThemeKey);
const toggleTheme = themeContext?.toggleTheme ?? (() => {});
</script>

<template>
  <button @click="toggleTheme">Toggle Theme</button>
</template>
```

---

## Application-Level `provide`

For app-wide services (router, i18n, analytics), you can provide at the application level:

```typescript
// main.ts
import { createApp } from "vue";
import App from "./App.vue";
import { AnalyticsKey } from "./injection-keys";
import { AnalyticsService } from "./services/analytics";

const app = createApp(App);

// Provide at the app level — available everywhere
app.provide(AnalyticsKey, new AnalyticsService({
  apiKey: import.meta.env.VITE_ANALYTICS_KEY,
  debug: import.meta.env.DEV,
}));

app.mount("#app");
```

---

## `provide`/`inject` in Composables

A common pattern: a composable uses `provide` to register itself and `inject` to access the parent's context:

```typescript
// composables/useFormField.ts
import { inject, provide, type InjectionKey, type Ref } from "vue";

export interface FormContext {
  register: (name: string, value: Ref) => void;
  unregister: (name: string) => void;
  validate: () => Record<string, string>;
  isSubmitting: Ref<boolean>;
}

export const FormKey: InjectionKey<FormContext> = Symbol("form");

// Used in a form container component
export function provideForm(context: FormContext) {
  provide(FormKey, context);
}

// Used in form field components to access the parent form
export function useFormField(name: string, value: Ref) {
  const form = inject(FormKey);

  if (form) {
    form.register(name, value);
    onUnmounted(() => form.unregister(name));
  }

  return {
    isSubmitting: form?.isSubmitting ?? ref(false),
    hasForm: !!form,
  };
}
```

---

## When to Use Provide/Inject vs Pinia

| Use Case | Recommendation |
| --- | --- |
| Data needed by many deeply nested components in a subtree | `provide`/`inject` |
| Global app state shared across the entire application | Pinia store |
| Plugin/library authors exposing their service | `provide`/`inject` with Symbol key |
| Feature-specific state that shouldn't leave the feature module | Pinia store with a composed store factory |
| Theming, locale, auth context in a provider component | `provide`/`inject` |

---

## Troubleshooting

### `inject()` returns `undefined` when it should return a value

`inject()` returns `undefined` if: (1) no ancestor has called `provide()` with the same key, (2) the component is rendered outside the providing tree (e.g., in a `<Teleport>` that renders outside the tree hierarchy), or (3) the injection key doesn't match (different Symbol instances or different string values). Use typed Symbol keys to eliminate typos.

### Injected value is not reactive

If the provider passes a plain value (`provide("count", 0)`) instead of a ref (`provide("count", ref(0))`), the injected value is not reactive. Always provide refs or reactive objects when the value will change.

### TypeScript error: "Argument of type 'InjectionKey<T>' is not assignable to parameter..."

This occurs when you import the InjectionKey from one file in the provider and a different copy from a different import path in the consumer. Ensure both import from the exact same source module.
