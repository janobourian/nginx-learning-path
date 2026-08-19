# Module 16: Built-in Special Components — `Teleport`, `Suspense` & `KeepAlive`

**Track:** Vue — Progressive Web Framework
**Category:** Component Architecture & Rendering Pipelines

---

## The Special Built-In Components in Vue 3

Vue 3 ships with several high-performance, compiler-aware built-in components that solve advanced UI layout, asynchronous orchestration, and animation challenges:

1. **`<Teleport>`**: Mounts a portion of a component's template into a different DOM node outside the component hierarchy (essential for modals, tooltips, toasts, and dropdowns).
2. **`<Suspense>`**: Orchestrates nested asynchronous dependencies (async `setup()`, top-level `await`, lazy components) with declarative fallback and loading states.
3. **`<KeepAlive>`**: Caches inactive component instances in memory to preserve state, scroll positions, and avoid unnecessary re-mount cycles.
4. **`<Transition>` & `<TransitionGroup>`**: Applies animated enter/leave transitions to elements and lists.

---

## 1. `<Teleport>` — Breaking Out of the DOM Hierarchy

### Why Teleport Is Necessary

In CSS, positioning a modal or popover inside a deeply nested component can fail if any ancestor element has:

- `overflow: hidden` (clips the modal content)
- `transform`, `perspective`, or `filter` (creates a new stacking context, breaking `position: fixed`)
- `z-index` layering constraints

`<Teleport>` lets you write modal logic inside the component where the trigger lives, while rendering the actual HTML elements into `<body>` or `<div id="teleport-target">`.

```vue
<!-- components/ConfirmDialog.vue -->
<script setup lang="ts">
import { ref } from "vue";

const props = defineProps<{
  title: string;
  message: string;
}>();

const emit = defineEmits<{
  confirm: [];
  cancel: [];
}>();

const isOpen = ref(false);

function open() {
  isOpen.value = true;
}

function close() {
  isOpen.value = false;
}

function handleConfirm() {
  close();
  emit("confirm");
}

function handleCancel() {
  close();
  emit("cancel");
}

defineExpose({ open, close });
</script>

<template>
  <button @click="open" class="btn-trigger">Open Dialog</button>

  <!-- Teleport destination target -->
  <!-- :disabled="false" teleports to <body>; :disabled="true" renders in place -->
  <Teleport to="body" :disabled="false">
    <Transition name="modal-fade">
      <div v-if="isOpen" class="modal-backdrop" @click.self="handleCancel">
        <div class="modal-card" role="dialog" aria-modal="true">
          <header class="modal-header">
            <h3>{{ title }}</h3>
            <button @click="handleCancel" class="btn-close">×</button>
          </header>
          <div class="modal-body">
            <p>{{ message }}</p>
          </div>
          <footer class="modal-actions">
            <button @click="handleCancel" class="btn-secondary">Cancel</button>
            <button @click="handleConfirm" class="btn-danger">Confirm</button>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-backdrop {
  position: fixed;
  inset: 0;
  background-color: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}

.modal-card {
  background: white;
  border-radius: 8px;
  width: 90%;
  max-width: 500px;
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.2);
}

.modal-fade-enter-active,
.modal-fade-leave-active {
  transition: opacity 0.2s ease;
}

.modal-fade-enter-from,
.modal-fade-leave-to {
  opacity: 0;
}
</style>
```

---

## 2. `<Suspense>` — Async Component Orchestration

`<Suspense>` allows declaring a unified loading boundary for any child component tree containing top-level `await` expressions or async `setup()` functions.

```vue
<!-- components/UserProfileAsync.vue (Async Component with top-level await) -->
<script setup lang="ts">
// Top-level await makes this an asynchronous component
const userId = "user_42";
const res = await fetch(`https://api.example.com/users/${userId}`);
const user = await res.json();
</script>

<template>
  <div class="user-profile">
    <h2>{{ user.name }}</h2>
    <p>{{ user.bio }}</p>
  </div>
</template>
```

```vue
<!-- views/DashboardView.vue (Parent with Suspense Boundary) -->
<script setup lang="ts">
import { ref, onErrorCaptured } from "vue";
import UserProfileAsync from "@/components/UserProfileAsync.vue";
import ActivityFeedAsync from "@/components/ActivityFeedAsync.vue";

const asyncError = ref<Error | null>(null);

// Error boundary: catch failures from async children
onErrorCaptured((err) => {
  asyncError.value = err as Error;
  return false; // Prevent error from propagating up
});
</script>

<template>
  <div class="dashboard-page">
    <h1>Account Dashboard</h1>

    <!-- Display error if async resolution fails -->
    <div v-if="asyncError" class="error-banner">
      <h3>Failed to load dashboard data</h3>
      <p>{{ asyncError.message }}</p>
      <button @click="asyncError = null">Retry</button>
    </div>

    <!-- Suspense Boundary -->
    <Suspense v-else>
      <!-- #default: Rendered when ALL async child components have resolved -->
      <template #default>
        <div class="dashboard-grid">
          <UserProfileAsync />
          <ActivityFeedAsync />
        </div>
      </template>

      <!-- #fallback: Rendered while ANY async child component is loading -->
      <template #fallback>
        <div class="skeleton-loader">
          <div class="skeleton-box" />
          <div class="skeleton-box" />
        </div>
      </template>
    </Suspense>
  </div>
</template>
```

---

## 3. `<KeepAlive>` — In-Memory Component Caching

`<KeepAlive>` caches inactive dynamic component instances instead of destroying and recreating them on every switch.

```vue
<script setup lang="ts">
import { ref, shallowRef } from "vue";
import TabOverview from "./tabs/TabOverview.vue";
import TabAnalytics from "./tabs/TabAnalytics.vue";
import TabSettings from "./tabs/TabSettings.vue";

const activeTab = shallowRef(TabOverview);
const tabs = [
  { name: "Overview", comp: TabOverview },
  { name: "Analytics", comp: TabAnalytics },
  { name: "Settings", comp: TabSettings },
];
</script>

<template>
  <nav class="tab-bar">
    <button
      v-for="tab in tabs"
      :key="tab.name"
      @click="activeTab = tab.comp"
    >
      {{ tab.name }}
    </button>
  </nav>

  <!-- KeepAlive with LRU cache limit and explicit inclusions -->
  <KeepAlive :max="5" :include="['TabOverview', 'TabAnalytics']">
    <component :is="activeTab" />
  </KeepAlive>
</template>
```

### KeepAlive Lifecycle Hooks

When a component is cached by `<KeepAlive>`, it does not unmount when deactivated. Instead, it triggers `onActivated` and `onDeactivated`:

```vue
<!-- tabs/TabAnalytics.vue -->
<script setup lang="ts">
import { onMounted, onUnmounted, onActivated, onDeactivated } from "vue";

let pollTimer: number | null = null;

function startPolling() {
  pollTimer = window.setInterval(() => {
    console.log("Fetching live analytics...");
  }, 3000);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

// Initial mount
onMounted(() => {
  console.log("TabAnalytics mounted for the first time");
});

// Resumed from KeepAlive cache
onActivated(() => {
  console.log("TabAnalytics activated — resuming live poll");
  startPolling();
});

// Paused and put into KeepAlive cache
onDeactivated(() => {
  console.log("TabAnalytics deactivated — pausing live poll");
  stopPolling();
});

// Component completely destroyed (when evicted from KeepAlive or app unmounts)
onUnmounted(() => {
  stopPolling();
});
</script>
```

---

## 4. `<TransitionGroup>` — FLIP List Animations

`<TransitionGroup>` animates list items when they are added, removed, or reordered using the FLIP (First, Last, Invert, Play) technique:

```vue
<!-- components/AnimatedTodoList.vue -->
<script setup lang="ts">
import { ref } from "vue";

const todos = ref([
  { id: 1, text: "Design System Tokens" },
  { id: 2, text: "Setup Vitest Unit Tests" },
  { id: 3, text: "Deploy Nuxt SSR to Edge" },
]);

function removeTodo(id: number) {
  todos.value = todos.value.filter((t) => t.id !== id);
}

function shuffleTodos() {
  todos.value = [...todos.value].sort(() => Math.random() - 0.5);
}
</script>

<template>
  <div class="todo-app">
    <button @click="shuffleTodos">Shuffle Order</button>

    <!-- TransitionGroup requires a :key on every child element -->
    <TransitionGroup name="list" tag="ul" class="todo-list">
      <li v-for="todo in todos" :key="todo.id" class="todo-item">
        <span>{{ todo.text }}</span>
        <button @click="removeTodo(todo.id)">Delete</button>
      </li>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.list-enter-active,
.list-leave-active {
  transition: all 0.3s ease;
}

.list-enter-from,
.list-leave-to {
  opacity: 0;
  transform: translateX(30px);
}

/* Ensure smooth FLIP animation for moving items */
.list-move {
  transition: transform 0.3s ease;
}

/* Ensure leaving elements don't disrupt list flow during exit */
.list-leave-active {
  position: absolute;
}
</style>
```

---

## Troubleshooting & Best Practices

1. **Teleport target does not exist**
   If `<Teleport to="#modal-root">` is evaluated before `<div id="modal-root">` exists in the DOM, Vue will throw an error. In SSR/Nuxt applications, make sure `#modal-root` is defined in `index.html` or `app.vue`.

2. **KeepAlive Component Names**
   The `:include` and `:exclude` props on `<KeepAlive>` match against the component's **`name`** option. In `<script setup>`, the name is inferred from the filename, or can be set explicitly via `defineOptions({ name: 'CustomName' })`.

3. **Suspense is Experimental**
   While widely used in production (especially within Nuxt 3), the standalone Vue `<Suspense>` API is marked as experimental in standard Vue core. Use Nuxt's async data wrappers (`useAsyncData`, `useFetch`) for stable SSR data orchestration.
