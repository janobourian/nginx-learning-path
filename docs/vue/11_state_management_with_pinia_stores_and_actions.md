# Module 11: State Management with Pinia — Stores, Getters & Actions

**Track:** Vue — Progressive Web Framework
**Category:** Global State Management

---

## What Is Pinia and Why Did It Replace Vuex?

**Pinia** is the official state management library for Vue. Designed from the ground up for Vue 3 and TypeScript, Pinia eliminates the friction, boilerplate, and design flaws of Vuex:

| Feature / Aspect | Vuex (v3 / v4) | Pinia |
| :--- | :--- | :--- |
| **Mutations** | Required (`commit('MUTATION')`) | **Eliminated** (Actions mutate state directly) |
| **TypeScript Support** | Poor, verbose custom type wrappers | **First-class**, full automatic type inference |
| **Nested Modules** | Complex namespace nesting (`'auth/user/login'`) | **Flat stores**, composed via direct imports |
| **Store Definition Syntax** | Single Options object | **Setup Stores** (Composition API) or **Option Stores** |
| **Bundle Size** | ~10KB minified | **~1.5KB** (Extremely lightweight) |
| **Devtools Support** | Limited time travel | Full time-travel debugging, action timeline, editing |

---

## Installing and Bootstrapping Pinia

```bash
npm install pinia
```

```typescript
// src/main.ts
import { createApp } from "vue";
import { createPinia } from "pinia";
import App from "./App.vue";

const app = createApp(App);
const pinia = createPinia();

app.use(pinia);
app.mount("#app");
```

---

## Store Paradigms: Option Stores vs Setup Stores

Pinia offers two syntaxes to define stores. Both produce identical reactive stores, but **Setup Stores** provide the maximum flexibility and natural alignment with the Composition API.

### 1. Option Stores (Familiar for Vuex migrants)

```typescript
// src/stores/counterOption.ts
import { defineStore } from "pinia";

export const useCounterOptionStore = defineStore("counterOption", {
  state: () => ({
    count: 0,
    name: "Alpha",
  }),
  getters: {
    doubleCount: (state) => state.count * 2,
    // Using `this` requires explicit return type in TypeScript
    doubleCountPlusOne(): number {
      return this.doubleCount + 1;
    },
  },
  actions: {
    increment() {
      this.count++;
    },
    async fetchInitialCount() {
      const res = await fetch("/api/count");
      const data = await res.json();
      this.count = data.value;
    },
  },
});
```

### 2. Setup Stores (Recommended for Modern Vue 3)

In Setup Stores:

- `ref()` / `reactive()` becomes **`state`**
- `computed()` becomes **`getters`**
- `function()` becomes **`actions`**

```typescript
// src/stores/cart.ts
import { defineStore } from "pinia";
import { ref, computed } from "vue";

export interface CartItem {
  id: string;
  title: string;
  price: number;
  quantity: number;
}

export const useCartStore = defineStore("cart", () => {
  // --- STATE ---
  const items = ref<CartItem[]>([]);
  const isCheckingOut = ref<boolean>(false);
  const promoCode = ref<string | null>(null);

  // --- GETTERS ---
  const itemCount = computed(() =>
    items.value.reduce((total, item) => total + item.quantity, 0)
  );

  const subtotal = computed(() =>
    items.value.reduce((total, item) => total + item.price * item.quantity, 0)
  );

  const discountRate = computed(() => {
    if (promoCode.value === "VUE20") return 0.20;
    if (promoCode.value === "SPRING10") return 0.10;
    return 0;
  });

  const total = computed(() => {
    const discounted = subtotal.value * (1 - discountRate.value);
    return Math.max(0, Number(discounted.toFixed(2)));
  });

  // --- ACTIONS ---
  function addItem(product: { id: string; title: string; price: number }) {
    const existing = items.value.find((i) => i.id === product.id);
    if (existing) {
      existing.quantity += 1;
    } else {
      items.value.push({ ...product, quantity: 1 });
    }
  }

  function removeItem(productId: string) {
    const index = items.value.findIndex((i) => i.id === productId);
    if (index !== -1) {
      items.value.splice(index, 1);
    }
  }

  function updateQuantity(productId: string, quantity: number) {
    const item = items.value.find((i) => i.id === productId);
    if (item) {
      if (quantity <= 0) {
        removeItem(productId);
      } else {
        item.quantity = quantity;
      }
    }
  }

  function applyPromo(code: string) {
    promoCode.value = code.trim().toUpperCase();
  }

  async function checkout(): Promise<{ success: boolean; orderId?: string }> {
    if (items.value.length === 0) {
      throw new Error("Cart is empty");
    }

    isCheckingOut.value = true;
    try {
      const response = await fetch("/api/orders/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          items: items.value,
          promoCode: promoCode.value,
          total: total.value,
        }),
      });

      if (!response.ok) {
        throw new Error("Checkout transaction failed");
      }

      const data = await response.json();
      items.value = [];
      promoCode.value = null;
      return { success: true, orderId: data.orderId };
    } finally {
      isCheckingOut.value = false;
    }
  }

  return {
    // State
    items,
    isCheckingOut,
    promoCode,
    // Getters
    itemCount,
    subtotal,
    discountRate,
    total,
    // Actions
    addItem,
    removeItem,
    updateQuantity,
    applyPromo,
    checkout,
  };
});
```

---

## Consuming Pinia Stores in Components

### The Destructuring Trap and `storeToRefs`

Direct destructuring of a Pinia store breaks reactivity because properties are extracted as raw values:

```typescript
// ❌ WRONG: Destructuring strips reactivity from state and getters!
const cart = useCartStore();
const { items, total } = cart; // total will never update!
```

```typescript
// ✅ CORRECT: Use storeToRefs() for state & getters; destructure actions directly!
import { storeToRefs } from "pinia";
import { useCartStore } from "@/stores/cart";

const cart = useCartStore();
// State & getters are wrapped into reactive refs:
const { items, total, itemCount, isCheckingOut } = storeToRefs(cart);
// Actions can be destructured directly as regular functions:
const { addItem, removeItem, checkout } = cart;
```

---

## Store Mutation & Subscription APIs

### 1. Batching Mutations with `$patch`

When updating multiple state properties simultaneously, `$patch` batches mutations into a single operation:

```typescript
const cart = useCartStore();

// Object syntax
cart.$patch({
  promoCode: "SUMMER",
});

// Function syntax (ideal for mutating arrays/nested objects without replacing them)
cart.$patch((state) => {
  state.items.push({ id: "99", title: "Free Sticker", price: 0, quantity: 1 });
  state.promoCode = "VIP";
});
```

### 2. Resetting State with `$reset`

In Option Stores, `store.$reset()` restores the state to its initial state. (In Setup Stores, you can create your own reset function).

### 3. State Subscription with `$subscribe`

Listen to state mutations (similar to Vuex plugins):

```typescript
cart.$subscribe((mutation, state) => {
  console.log("Mutation type:", mutation.type); // 'direct' | 'patch object' | 'patch function'
  console.log("Store ID:", mutation.storeId);
  // Persist cart to localStorage
  localStorage.setItem("shopping_cart", JSON.stringify(state.items));
}, { detached: true }); // detached: true keeps subscription active even after component unmounts
```

### 4. Action Subscription with `$onAction`

Track, intercept, and profile action executions:

```typescript
cart.$onAction(({ name, args, after, onError }) => {
  const startTime = Date.now();
  console.log(`Action "${name}" invoked with args:`, args);

  after((result) => {
    console.log(`Action "${name}" resolved in ${Date.now() - startTime}ms. Result:`, result);
  });

  onError((error) => {
    console.error(`Action "${name}" failed with error:`, error);
  });
});
```

---

## Pinia Plugins

Pinia can be extended with plugins to provide cross-cutting concerns like persistence, state history, analytics, or sync across browser tabs.

```typescript
// src/plugins/piniaPersist.ts
import type { PiniaPluginContext } from "pinia";

export function piniaLocalStoragePlugin(context: PiniaPluginContext) {
  const { store } = context;
  const storageKey = `pinia_store_${store.$id}`;

  // Restore state from LocalStorage on store initialization
  const savedState = localStorage.getItem(storageKey);
  if (savedState) {
    try {
      store.$patch(JSON.parse(savedState));
    } catch (e) {
      console.error(`Failed to restore state for store ${store.$id}:`, e);
    }
  }

  // Subscribe to all changes and write to LocalStorage
  store.$subscribe((_mutation, state) => {
    localStorage.setItem(storageKey, JSON.stringify(state));
  });
}
```

```typescript
// src/main.ts
import { createPinia } from "pinia";
import { piniaLocalStoragePlugin } from "./plugins/piniaPersist";

const pinia = createPinia();
pinia.use(piniaLocalStoragePlugin);
```

---

## Cross-Store Composition

Because Pinia stores are flat, one store can easily invoke and consume another store:

```typescript
// src/stores/order.ts
import { defineStore } from "pinia";
import { ref } from "vue";
import { useCartStore } from "./cart";
import { useUserStore } from "./user";

export const useOrderStore = defineStore("order", () => {
  const cart = useCartStore();
  const user = useUserStore();
  const orderHistory = ref([]);

  async function submitCurrentCartAsOrder() {
    if (!user.isAuthenticated) {
      throw new Error("User must be logged in to order");
    }

    const payload = {
      userId: user.profile.id,
      items: cart.items,
      total: cart.total,
    };

    const response = await fetch("/api/orders", {
      method: "POST",
      body: JSON.stringify(payload),
    });

    const newOrder = await response.json();
    orderHistory.value.push(newOrder);
    cart.items = []; // Clear cart on success
    return newOrder;
  }

  return {
    orderHistory,
    submitCurrentCartAsOrder,
  };
});
```

---

## Troubleshooting & Best Practices

1. **Do NOT invoke stores outside setup / active Pinia context during initialization**

   ```typescript
   // ❌ WRONG: Called before app.use(pinia) runs
   const store = useCartStore();
   export default { ... }

   // ✅ CORRECT: Invoke useCartStore() inside setup(), hooks, or route guards
   ```

2. **Always use `storeToRefs` when destructuring state/getters**
   Missing `storeToRefs` is the single most common cause of "my component didn't re-render on state change" bugs in Vue 3.

3. **Avoid monolithic stores**
   Break state down into domain-driven stores (`useAuthStore`, `useProductCatalogStore`, `useNotificationStore`) rather than creating a single massive global state container.
