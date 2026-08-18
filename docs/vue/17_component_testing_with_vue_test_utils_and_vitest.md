# Module 17: Component Testing — Vue Test Utils, Vitest & Pinia Mocking

**Track:** Vue — Progressive Web Framework  
**Category:** Quality Assurance & Automated Testing

---

## The Modern Vue Testing Stack: Vitest & `@vue/test-utils`

**Vitest** is the standard test runner for modern Vue applications. Built natively on Vite, it shares the exact same plugin pipeline, transform rules, and `resolve.alias` paths as your development and production builds.

Coupled with **`@vue/test-utils`** (the official testing utility library for Vue 3) and **`happy-dom`** or **`jsdom`**, Vitest provides sub-millisecond test execution speeds with zero configuration drift.

---

## Setting Up Vitest & Test Utilities

```bash
npm install -D vitest @vue/test-utils happy-dom @pinia/testing
```

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  test: {
    globals: true,
    environment: "happy-dom", // Fast DOM implementation
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },
  },
});
```

---

## Unit Testing a Vue Component with User Interactions

Let's test an interactive shopping cart item component that emits events and accepts props:

```vue
<!-- src/components/CartItem.vue -->
<script setup lang="ts">
const props = defineProps<{
  id: string;
  name: string;
  price: number;
  quantity: number;
}>();

const emit = defineEmits<{
  updateQuantity: [id: string, quantity: number];
  remove: [id: string];
}>();

function increment() {
  emit("updateQuantity", props.id, props.quantity + 1);
}

function decrement() {
  if (props.quantity > 1) {
    emit("updateQuantity", props.id, props.quantity - 1);
  }
}
</script>

<template>
  <div class="cart-item" :data-id="props.id">
    <span class="item-name">{{ props.name }}</span>
    <span class="item-price">${{ (props.price * props.quantity).toFixed(2) }}</span>

    <div class="quantity-controls">
      <button class="btn-dec" :disabled="props.quantity <= 1" @click="decrement">-</button>
      <span class="quantity-value">{{ props.quantity }}</span>
      <button class="btn-inc" @click="increment">+</button>
    </div>

    <button class="btn-remove" @click="emit('remove', props.id)">Delete</button>
  </div>
</template>
```

### Comprehensive Component Test Suite

```typescript
// tests/unit/CartItem.spec.ts
import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import CartItem from "@/components/CartItem.vue";

describe("CartItem.vue", () => {
  const defaultProps = {
    id: "item_123",
    name: "Wireless Mouse",
    price: 29.99,
    quantity: 2,
  };

  it("renders item name and computed subtotal correctly", () => {
    const wrapper = mount(CartItem, {
      props: defaultProps,
    });

    expect(wrapper.find(".item-name").text()).toBe("Wireless Mouse");
    expect(wrapper.find(".item-price").text()).toBe("$59.98");
    expect(wrapper.find(".quantity-value").text()).toBe("2");
  });

  it("emits updateQuantity with incremented value on '+' click", async () => {
    const wrapper = mount(CartItem, {
      props: defaultProps,
    });

    await wrapper.find(".btn-inc").trigger("click");

    // Assert emitted event was captured
    expect(wrapper.emitted("updateQuantity")).toBeTruthy();
    expect(wrapper.emitted("updateQuantity")![0]).toEqual(["item_123", 3]);
  });

  it("disables decrement button when quantity is 1", () => {
    const wrapper = mount(CartItem, {
      props: { ...defaultProps, quantity: 1 },
    });

    const decBtn = wrapper.find(".btn-dec");
    expect(decBtn.attributes("disabled")).toBeDefined();
  });

  it("emits remove event with item ID on delete click", async () => {
    const wrapper = mount(CartItem, {
      props: defaultProps,
    });

    await wrapper.find(".btn-remove").trigger("click");

    expect(wrapper.emitted("remove")).toHaveLength(1);
    expect(wrapper.emitted("remove")![0]).toEqual(["item_123"]);
  });
});
```

---

## Testing Components with Pinia Stores (`@pinia/testing`)

`createTestingPinia()` mocks all store actions by default (preventing real HTTP requests) while keeping state and getters fully reactive:

```vue
<!-- src/components/UserProfile.vue -->
<script setup lang="ts">
import { useAuthStore } from "@/stores/auth";

const auth = useAuthStore();
</script>

<template>
  <div class="user-profile">
    <div v-if="auth.isAuthenticated">
      <h2>Welcome, {{ auth.user?.name }}!</h2>
      <button @click="auth.logout()">Log Out</button>
    </div>
    <div v-else>
      <button @click="auth.login()">Log In</button>
    </div>
  </div>
</template>
```

```typescript
// tests/unit/UserProfile.spec.ts
import { describe, it, expect, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createTestingPinia } from "@pinia/testing";
import UserProfile from "@/components/UserProfile.vue";
import { useAuthStore } from "@/stores/auth";

describe("UserProfile.vue with Pinia", () => {
  it("renders login button when unauthenticated", () => {
    const wrapper = mount(UserProfile, {
      global: {
        plugins: [
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              auth: { isAuthenticated: false, user: null },
            },
          }),
        ],
      },
    });

    expect(wrapper.text()).toContain("Log In");
  });

  it("renders user name and invokes logout action on button click", async () => {
    const wrapper = mount(UserProfile, {
      global: {
        plugins: [
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              auth: {
                isAuthenticated: true,
                user: { name: "Alice Chen" },
              },
            },
          }),
        ],
      },
    });

    const store = useAuthStore();

    expect(wrapper.text()).toContain("Welcome, Alice Chen!");

    await wrapper.find("button").trigger("click");

    // Assert that the store's logout action was called
    expect(store.logout).toHaveBeenCalledTimes(1);
  });
});
```

---

## Testing Custom Composables in Isolation

Composables that rely on Vue's lifecycle hooks (`onMounted`, `onUnmounted`) or `provide`/`inject` must be executed within an active component context. Use the `withSetup` helper pattern:

```typescript
// tests/helpers/withSetup.ts
import { createApp, type App } from "vue";

export function withSetup<T>(composable: () => T): [T, App] {
  let result: T;

  const app = createApp({
    setup() {
      result = composable();
      return () => {};
    },
  });

  app.mount(document.createElement("div"));

  return [result!, app];
}
```

```typescript
// tests/unit/useCounter.spec.ts
import { describe, it, expect } from "vitest";
import { useCounter } from "@/composables/useCounter";
import { withSetup } from "../helpers/withSetup";

describe("useCounter composable", () => {
  it("increments and decrements counter state", () => {
    const [{ count, increment, decrement }] = withSetup(() => useCounter(10));

    expect(count.value).toBe(10);

    increment();
    expect(count.value).toBe(11);

    decrement();
    expect(count.value).toBe(10);
  });
});
```

---

## Testing Vue Router Integrations

```typescript
// tests/unit/Navigation.spec.ts
import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import { createRouter, createMemoryHistory } from "vue-router";
import AppNav from "@/components/AppNav.vue";

describe("AppNav.vue with Vue Router", () => {
  it("navigates to target route when link is clicked", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/", name: "home", component: { template: "Home" } },
        { path: "/about", name: "about", component: { template: "About" } },
      ],
    });

    const wrapper = mount(AppNav, {
      global: {
        plugins: [router],
      },
    });

    await router.isReady();

    // Click navigation link
    await wrapper.find('a[href="/about"]').trigger("click");
    await router.isReady();

    expect(router.currentRoute.value.path).toBe("/about");
  });
});
```

---

## Troubleshooting & Best Practices

1. **DOM updates not reflected after triggering events**
   Triggering events with `await wrapper.trigger('click')` automatically awaits `nextTick()`. However, if the action triggers an async promise (like an API call), use `await flushPromises()` from `@vue/test-utils` to wait for microtask resolution.

2. **Mount vs ShallowMount**
   - Use `mount()` for testing components with their full child trees or integration tests.
   - Use `shallowMount()` or stub child components (`global: { stubs: { HeavyChart: true } }`) to isolate a unit test from heavy dependencies.

3. **Clean up DOM between test runs**
   Vitest and happy-dom reset the DOM automatically between tests if `globals: true` is configured in `vitest.config.ts`.
