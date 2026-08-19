# Module 07: Component Architecture — `defineProps`, `defineEmits` & Patterns

**Track:** Vue — Progressive Web Framework
**Category:** Component Communication & Design Patterns

---

## Component Communication Model

Vue uses a **unidirectional data flow**: data flows down from parent to child via props, and events flow up from child to parent via emits. This makes component relationships explicit and traceable.

```text
Parent Component
  │
  │   Props (data flows down)
  ▼
Child Component
  │
  │   Emits (events flow up)
  ▼
Parent Component (handles the event)
```

---

## `defineProps()` — Receiving Data from Parent

```vue
<!-- components/ProductCard.vue -->
<script setup lang="ts">
// TypeScript generic syntax (recommended in Vue 3.3+)
interface Props {
  id: string;
  name: string;
  price: number;
  description?: string;   // Optional prop
  inStock: boolean;
  category: "electronics" | "furniture" | "clothing";
  tags?: string[];
  rating?: number;
}

// withDefaults provides default values for optional props
const props = withDefaults(defineProps<Props>(), {
  description: "No description available",
  inStock: true,
  tags: () => [],           // Factory function for object/array defaults!
  rating: 0,
});

// Props are read-only — never mutate them
// ❌ props.name = "New Name";  // Runtime warning
// ✅ Emit an event to ask parent to change the value
</script>

<template>
  <div class="product-card" :class="{ 'out-of-stock': !props.inStock }">
    <h3>{{ props.name }}</h3>
    <p class="price">${{ props.price.toFixed(2) }}</p>
    <p class="description">{{ props.description }}</p>

    <!-- Category renders as a formatted badge -->
    <span class="badge">{{ props.category }}</span>

    <!-- Tags render conditionally -->
    <div v-if="props.tags?.length" class="tags">
      <span v-for="tag in props.tags" :key="tag" class="tag">{{ tag }}</span>
    </div>

    <div class="rating">
      <span v-for="i in 5" :key="i" :class="{ filled: i <= (props.rating ?? 0) }">★</span>
    </div>
  </div>
</template>
```

### Runtime Props Validation (Alternative to TypeScript)

```typescript
// Runtime validation (useful without TypeScript or for additional constraints)
const props = defineProps({
  price: {
    type: Number,
    required: true,
    validator: (value: number) => value >= 0, // Must be non-negative
  },
  category: {
    type: String,
    default: "general",
    validator: (val: string) => ["electronics", "furniture", "clothing"].includes(val),
  },
  tags: {
    type: Array as PropType<string[]>,
    default: () => [],
  },
});
```

---

## `defineEmits()` — Sending Events to Parent

```vue
<!-- components/LoginForm.vue -->
<script setup lang="ts">
import { ref } from "vue";

// TypeScript syntax: define events with their payload types
const emit = defineEmits<{
  submit: [credentials: { email: string; password: string }];
  cancel: [];        // No payload
  "forgot-password": [email: string];
  error: [message: string, code: number];
}>();

const email = ref("");
const password = ref("");
const isLoading = ref(false);

async function handleSubmit() {
  if (!email.value || !password.value) {
    emit("error", "Email and password are required", 400);
    return;
  }

  isLoading.value = true;
  emit("submit", { email: email.value, password: password.value });
}

function handleForgotPassword() {
  emit("forgot-password", email.value);
}
</script>

<template>
  <form @submit.prevent="handleSubmit">
    <input v-model="email" type="email" placeholder="Email" />
    <input v-model="password" type="password" placeholder="Password" />
    <button type="submit" :disabled="isLoading">
      {{ isLoading ? "Signing in..." : "Sign In" }}
    </button>
    <button type="button" @click="emit('cancel')">Cancel</button>
    <button type="button" @click="handleForgotPassword">Forgot Password?</button>
  </form>
</template>
```

Using the component in a parent:

```vue
<!-- views/LoginPage.vue -->
<script setup lang="ts">
import { useRouter } from "vue-router";
import LoginForm from "@/components/LoginForm.vue";

const router = useRouter();

async function onLogin(credentials: { email: string; password: string }) {
  try {
    await authService.login(credentials);
    router.push("/dashboard");
  } catch {
    // Handle error
  }
}

function onForgotPassword(email: string) {
  router.push({ name: "forgot-password", query: { email } });
}

function onError(message: string, code: number) {
  console.error(`Auth error ${code}: ${message}`);
}
</script>

<template>
  <div class="auth-page">
    <LoginForm
      @submit="onLogin"
      @cancel="router.push('/')"
      @forgot-password="onForgotPassword"
      @error="onError"
    />
  </div>
</template>
```

---

## `defineExpose()` — Exposing Component Methods

By default, `<script setup>` components are completely closed — parent components cannot access their internal state or methods via template refs. `defineExpose()` deliberately exposes specific internals:

```vue
<!-- components/AppModal.vue -->
<script setup lang="ts">
import { ref } from "vue";

const isOpen = ref(false);
const title = ref("");

function open(modalTitle: string = "Modal") {
  title.value = modalTitle;
  isOpen.value = true;
}

function close() {
  isOpen.value = false;
}

// Only these methods are accessible from the parent via template ref
defineExpose({ open, close });
</script>

<template>
  <Teleport to="body">
    <div v-if="isOpen" class="modal-overlay" @click.self="close">
      <div class="modal">
        <h2>{{ title }}</h2>
        <slot />
        <button @click="close">Close</button>
      </div>
    </div>
  </Teleport>
</template>
```

```vue
<!-- Using the modal -->
<script setup lang="ts">
import { ref } from "vue";
import AppModal from "@/components/AppModal.vue";

const modalRef = ref<InstanceType<typeof AppModal> | null>(null);

function openDeleteConfirm() {
  modalRef.value?.open("Confirm Delete");
}
</script>

<template>
  <AppModal ref="modalRef">
    <p>Are you sure you want to delete this item?</p>
    <button @click="deleteItem">Delete</button>
  </AppModal>

  <button @click="openDeleteConfirm">Delete Item</button>
</template>
```

---

## Component Design Patterns

### Container/Presenter (Smart/Dumb) Pattern

```vue
<!-- Presenter (Dumb): only displays data, emits events -->
<!-- components/UserList.vue -->
<script setup lang="ts">
interface User { id: string; name: string; email: string; active: boolean; }
defineProps<{ users: User[]; isLoading: boolean; }>();
defineEmits<{ "activate": [id: string]; "deactivate": [id: string]; "delete": [id: string]; }>();
</script>

<template>
  <div v-if="isLoading">Loading...</div>
  <table v-else>
    <tbody>
      <tr v-for="user in users" :key="user.id">
        <td>{{ user.name }}</td>
        <td>{{ user.email }}</td>
        <td>
          <button v-if="!user.active" @click="$emit('activate', user.id)">Activate</button>
          <button v-else @click="$emit('deactivate', user.id)">Deactivate</button>
          <button @click="$emit('delete', user.id)">Delete</button>
        </td>
      </tr>
    </tbody>
  </table>
</template>
```

```vue
<!-- Container (Smart): handles data fetching and state management -->
<!-- views/UsersView.vue -->
<script setup lang="ts">
import { ref, onMounted } from "vue";
import UserList from "@/components/UserList.vue";
import { useUsersStore } from "@/stores/users";

const store = useUsersStore();
onMounted(() => store.fetchUsers());
</script>

<template>
  <UserList
    :users="store.users"
    :is-loading="store.isLoading"
    @activate="store.activateUser($event)"
    @deactivate="store.deactivateUser($event)"
    @delete="store.deleteUser($event)"
  />
</template>
```

### Renderless Component Pattern

A renderless component provides logic without any HTML — the parent controls the rendering via scoped slots:

```vue
<!-- components/Pagination.vue — renderless logic component -->
<script setup lang="ts">
import { computed } from "vue";

const props = defineProps<{
  total: number;
  pageSize: number;
  currentPage: number;
}>();

const emit = defineEmits<{ "update:currentPage": [page: number] }>();

const totalPages = computed(() => Math.ceil(props.total / props.pageSize));
const hasPrev = computed(() => props.currentPage > 1);
const hasNext = computed(() => props.currentPage < totalPages.value);

const visiblePages = computed(() => {
  const start = Math.max(1, props.currentPage - 2);
  const end = Math.min(totalPages.value, props.currentPage + 2);
  return Array.from({ length: end - start + 1 }, (_, i) => start + i);
});

function goTo(page: number) {
  if (page >= 1 && page <= totalPages.value) {
    emit("update:currentPage", page);
  }
}
</script>

<template>
  <!-- Renderless: only exposes slot with state and methods -->
  <slot
    :current-page="currentPage"
    :total-pages="totalPages"
    :has-prev="hasPrev"
    :has-next="hasNext"
    :visible-pages="visiblePages"
    :go-to="goTo"
    :go-prev="() => goTo(currentPage - 1)"
    :go-next="() => goTo(currentPage + 1)"
  />
</template>
```

---

## Troubleshooting

### "Missing required prop" warning even though the prop is passed

The prop name in the parent must be kebab-case (`my-prop`) when the child defines it in camelCase (`myProp`). Vue automatically converts these. But if you pass `:myProp="value"` (camelCase attribute) in the template, Vue does NOT auto-convert — use `:my-prop="value"` or `:myProp` in JSX.

### `defineExpose` method shows as undefined in parent's template ref

The parent's `ref` is populated only after the child mounts. Access `childRef.value?.method()` inside `onMounted()` or later lifecycle hooks, not at the top level of `<script setup>`.

### TypeScript error: "Property 'x' does not exist on type '{}'"

The `defineEmits` payload type may be wrong. For `emit("change", value)` where value is a string, define: `defineEmits<{ change: [value: string] }>()`. The array syntax `[value: string]` represents the tuple of arguments after the event name.
