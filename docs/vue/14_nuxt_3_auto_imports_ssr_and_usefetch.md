# Module 14: Nuxt 3 — Auto-Imports, SSR Data Fetching & `useFetch`

**Track:** Vue — Progressive Web Framework
**Category:** Universal Data Fetching & Hydration

---

## The Auto-Imports Engine in Nuxt 3

Nuxt 3 automatically imports functions, composables, and components throughout your application, dramatically reducing boilerplate:

1. **Vue 3 & Nuxt APIs**: `ref`, `computed`, `watch`, `onMounted`, `useRoute`, `useRouter`, `useHead`, `useFetch`, `useState` are always available globally without explicit `import { ref } from 'vue'` statements.
2. **Components (`components/`)**: A component at `components/AppButton.vue` is immediately usable as `<AppButton />` or `<app-button />` in any template. Nested components like `components/user/ProfileCard.vue` auto-resolve as `<UserProfileCard />`.
3. **Custom Composables (`composables/`)**: Any exported function in `composables/*.ts` is automatically available across all pages, components, and other composables.
4. **Server Utilities (`server/utils/`)**: Helper functions in `server/utils/*.ts` are auto-imported into all Nitro server route handlers.

---

## Universal Data Fetching: Why Standard `fetch()` Fails in SSR

In a universal SSR environment:

1. The server renders the page and calls `fetch("/api/posts")`.
2. The HTML is sent to the client browser.
3. If the client component runs `onMounted(() => fetch("/api/posts"))`, the network request runs **a second time**, causing wasted bandwidth, delayed hydration, and flickering UI.

Nuxt 3 provides composables (`useFetch`, `useAsyncData`, `useState`) that **fetch data on the server, serialize the result into the page payload, and hydrate the client state instantly without a second network request**.

```text
Universal Data Flow:
Server Execution:
  useFetch('/api/posts') ──► Nitro/Backend ──► Data fetched ──► Serialized into <script id="__NUXT_DATA__">
                                                                       │
                                                                       ▼
Browser Hydration:                                             HTML Stream with JSON Payload
  useFetch('/api/posts') reads deserialized payload instantly ◄────────┘
  (No second HTTP network call occurs!)
```

---

## `useFetch` vs `useAsyncData` vs `$fetch`

| Function | Primary Purpose | SSR Payload Hydration | Reactive Source Watching |
| :--- | :--- | :--- | :--- |
| **`useFetch(url, opts)`** | Top-level component HTTP queries | **Yes** (Built-in) | **Yes** (Auto-refetches on query/param change) |
| **`useAsyncData(key, handler)`** | Custom async logic (multi-fetch, DB query, third-party SDK) | **Yes** (Requires unique key) | **Yes** (Via `watch` option) |
| **`$fetch(url, opts)`** | Event handlers (button clicks, form submits) | **No** (Direct network call) | **No** |

---

## Mastering `useFetch`

```vue
<!-- pages/products/index.vue -->
<script setup lang="ts">
interface Product {
  id: string;
  title: string;
  price: number;
  category: string;
  rating: number;
}

interface ProductResponse {
  products: Product[];
  total: number;
  page: number;
}

const route = useRoute();
const page = ref(Number(route.query.page) || 1);
const selectedCategory = ref(route.query.category?.toString() || "all");
const searchQuery = ref("");

// useFetch automatically generates a cache key based on URL & parameters
// When `page` or `selectedCategory` changes, useFetch automatically triggers a re-fetch!
const {
  data: response,
  pending: isLoading,
  error,
  refresh,
} = await useFetch<ProductResponse>("/api/products", {
  method: "GET",
  query: {
    page,
    category: selectedCategory,
    q: searchQuery,
  },
  // Transform raw response to pluck or format data before caching
  transform: (res) => ({
    ...res,
    products: res.products.map((p) => ({
      ...p,
      title: p.title.toUpperCase(),
    })),
  }),
  // Pick only specific fields for the client bundle to reduce payload size
  pick: ["products", "total", "page"],
  // Watch reactive variables explicitly if needed
  watch: [page, selectedCategory],
});
</script>

<template>
  <div class="product-catalog">
    <header class="controls">
      <input
        v-model.lazy="searchQuery"
        type="text"
        placeholder="Search products..."
      />
      <select v-model="selectedCategory">
        <option value="all">All Categories</option>
        <option value="electronics">Electronics</option>
        <option value="furniture">Furniture</option>
      </select>
      <button @click="() => refresh()" :disabled="isLoading">
        {{ isLoading ? "Refreshing..." : "Refresh" }}
      </button>
    </header>

    <!-- Error State -->
    <div v-if="error" class="error-banner">
      <h3>Failed to load products</h3>
      <p>{{ error.message }}</p>
      <button @click="() => refresh()">Retry</button>
    </div>

    <!-- Loading Skeleton -->
    <div v-else-if="isLoading" class="skeleton-grid">
      <div v-for="n in 6" :key="n" class="skeleton-card" />
    </div>

    <!-- Product Grid -->
    <div v-else-if="response?.products.length" class="grid">
      <article
        v-for="product in response.products"
        :key="product.id"
        class="product-card"
      >
        <h3>{{ product.title }}</h3>
        <p class="price">${{ product.price.toFixed(2) }}</p>
      </article>
    </div>

    <!-- Pagination Controls -->
    <footer class="pagination">
      <button :disabled="page <= 1" @click="page--">Previous</button>
      <span>Page {{ page }}</span>
      <button @click="page++">Next</button>
    </footer>
  </div>
</template>
```

---

## Non-Blocking Lazy Data Fetching (`useLazyFetch`)

By default, top-level `await useFetch(...)` blocks page route navigation until the server finishes the request.

For high-latency APIs where you want instant page transitions with client-side loading skeletons, use `useLazyFetch` (or `lazy: true`):

```vue
<!-- pages/dashboard.vue -->
<script setup lang="ts">
// Navigation happens immediately! pending is true while data loads
const { data: analytics, pending } = useLazyFetch("/api/heavy-analytics", {
  server: true, // Still executes on server if initial load
});
</script>

<template>
  <div>
    <h1>Dashboard Analytics</h1>
    <div v-if="pending" class="loading-spinner">
      Generating real-time statistics...
    </div>
    <div v-else class="charts">
      <pre>{{ analytics }}</pre>
    </div>
  </div>
</template>
```

---

## `useAsyncData` for Complex Multi-Source Fetching

When combining multiple API calls or querying an ORM/database directly, use `useAsyncData`:

```vue
<!-- pages/posts/[id].vue -->
<script setup lang="ts">
const route = useRoute();
const postId = route.params.id as string;

// Provide an explicit unique key ('post-detail-123') for hydration cache
const { data, error } = await useAsyncData(`post-detail-${postId}`, async () => {
  // Fetch post and comments in parallel
  const [post, comments, author] = await Promise.all([
    $fetch(`/api/posts/${postId}`),
    $fetch(`/api/posts/${postId}/comments`),
    $fetch(`/api/users/by-post/${postId}`),
  ]);

  return {
    post,
    comments,
    author,
  };
});
</script>
```

---

## Universal Reactive State with `useState`

`useState` is an SSR-friendly alternative to `ref()` for global or shared state. Unlike a standard `ref()`, state created with `useState` is **serialized on the server and transferred to the client payload**, preventing state mismatches during hydration.

```typescript
// composables/useUserSession.ts
export interface UserSession {
  id: string;
  email: string;
  name: string;
  role: "admin" | "user";
}

export function useUserSession() {
  // Keyed universal state (shared across all components and SSR payload)
  const session = useState<UserSession | null>("user-session", () => null);
  const isAuthenticated = computed(() => Boolean(session.value));

  const setSession = (userData: UserSession) => {
    session.value = userData;
  };

  const clearSession = () => {
    session.value = null;
  };

  return {
    session,
    isAuthenticated,
    setSession,
    clearSession,
  };
}
```

---

## Performing Mutations with `$fetch` in Event Handlers

Never use `useFetch` inside event handlers (like form submits or click listeners) — composables must only be invoked during component setup. Use `$fetch` for event-driven mutations:

```vue
<!-- components/CreateCommentForm.vue -->
<script setup lang="ts">
const props = defineProps<{ postId: string }>();
const emit = defineEmits<{ commentCreated: [] }>();

const commentText = ref("");
const isSubmitting = ref(false);
const errorMessage = ref<string | null>(null);

async function submitComment() {
  if (!commentText.value.trim()) return;

  isSubmitting.value = true;
  errorMessage.value = null;

  try {
    // $fetch makes a standard HTTP request without SSR payload overhead
    await $fetch(`/api/posts/${props.postId}/comments`, {
      method: "POST",
      body: { content: commentText.value },
    });

    commentText.value = "";
    emit("commentCreated");
  } catch (err: any) {
    errorMessage.value = err.data?.message || err.message;
  } finally {
    isSubmitting.value = false;
  }
}
</script>

<template>
  <form @submit.prevent="submitComment">
    <textarea v-model="commentText" placeholder="Write a comment..." />
    <span v-if="errorMessage" class="error">{{ errorMessage }}</span>
    <button type="submit" :disabled="isSubmitting">
      {{ isSubmitting ? "Posting..." : "Post Comment" }}
    </button>
  </form>
</template>
```

---

## Troubleshooting & Best Practices

1. **Duplicate key warnings in `useAsyncData`**
   Always ensure keys passed to `useAsyncData('key', ...)` are unique per resource, e.g., `useAsyncData('user-' + id, ...)`. Reusing static keys for different dynamic records will cause stale cache bugs.

2. **Accidentally using `useFetch` inside an async function or click handler**

   ```typescript
   // ❌ WRONG: useFetch inside click handler
   async function onClick() {
     const { data } = await useFetch('/api/action'); // Violates Composition API rules!
   }

   // ✅ CORRECT: Use $fetch for event triggers
   async function onClick() {
     const data = await $fetch('/api/action', { method: 'POST' });
   }
   ```

3. **Missing reactive query params**
   When passing dynamic queries to `useFetch`, pass the reactive `ref` directly inside the `query` object (e.g. `query: { page }`), not the raw unwrap `query: { page: page.value }`. Passing the ref allows `useFetch` to watch for changes and auto-refresh.
