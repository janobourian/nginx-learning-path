# Module 12: Vue Router 4 — Dynamic Routing, Nested Routes & Navigation Guards

**Track:** Vue — Progressive Web Framework
**Category:** Single Page Application (SPA) Routing

---

## What Is Vue Router 4?

**Vue Router 4** is the official router for Vue 3. It maps browser URLs to Vue component trees, manages browser history (HTML5 History API or Hash mode), provides sophisticated navigation guards for authentication/authorization, and enables route-level code splitting.

---

## Installation & Basic Router Setup

```bash
npm install vue-router@4
```

```typescript
// src/router/index.ts
import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";

// Lazy-loaded route components for optimal bundle splitting
const HomeView = () => import("@/views/HomeView.vue");
const AboutView = () => import("@/views/AboutView.vue");
const UserProfileView = () => import("@/views/UserProfileView.vue");
const NotFoundView = () => import("@/views/NotFoundView.vue");

const routes: RouteRecordRaw[] = [
  {
    path: "/",
    name: "home",
    component: HomeView,
    meta: { requiresAuth: false, title: "Home" },
  },
  {
    path: "/about",
    name: "about",
    component: AboutView,
    meta: { requiresAuth: false, title: "About Us" },
  },
  {
    path: "/users/:id",
    name: "user-profile",
    component: UserProfileView,
    props: true, // Passes route.params as component props directly!
    meta: { requiresAuth: true, title: "User Profile" },
  },
  // Catch-all 404 route
  {
    path: "/:pathMatch(.*)*",
    name: "not-found",
    component: NotFoundView,
    meta: { title: "404 Not Found" },
  },
];

export const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
  scrollBehavior(to, from, savedPosition) {
    if (savedPosition) {
      return savedPosition; // Back/forward browser buttons restore scroll
    }
    if (to.hash) {
      return { el: to.hash, behavior: "smooth" };
    }
    return { top: 0 };
  },
});
```

```typescript
// src/main.ts
import { createApp } from "vue";
import App from "./App.vue";
import { router } from "./router";

const app = createApp(App);
app.use(router);
app.mount("#app");
```

---

## Dynamic Routing & Route Parameters

Route parameters extract variables from the path:

```typescript
// Route definition
{
  path: "/orgs/:orgId/projects/:projectId(\\d+)", // regex constraint: projectId must be digits
  name: "project-detail",
  component: ProjectDetailView,
  props: (route) => ({
    orgId: route.params.orgId,
    projectId: Number(route.params.projectId),
    tab: route.query.tab || "overview",
  }),
}
```

### Accessing Route Data in Components

```vue
<!-- src/views/UserProfileView.vue -->
<script setup lang="ts">
import { ref, watch, onMounted } from "vue";
import { useRoute, useRouter, onBeforeRouteUpdate, onBeforeRouteLeave } from "vue-router";

// 1. If props: true was configured in route definition:
const props = defineProps<{ id: string }>();

// 2. Programmatic access via composables:
const route = useRoute();
const router = useRouter();

const userData = ref<any>(null);
const isLoading = ref(false);

async function loadUserData(userId: string) {
  isLoading.value = true;
  try {
    const res = await fetch(`/api/users/${userId}`);
    userData.value = await res.json();
  } finally {
    isLoading.value = false;
  }
}

onMounted(() => {
  loadUserData(props.id || (route.params.id as string));
});

// React to param changes when navigating between /users/1 -> /users/2 without re-mounting
onBeforeRouteUpdate(async (to, from) => {
  if (to.params.id !== from.params.id) {
    await loadUserData(to.params.id as string);
  }
});

// Prevent accidental navigation if user has unsaved edits
const hasUnsavedChanges = ref(false);
onBeforeRouteLeave((to, from) => {
  if (hasUnsavedChanges.value) {
    const confirm = window.confirm("You have unsaved changes! Do you really want to leave?");
    if (!confirm) return false; // Cancel navigation
  }
});

function goToSettings() {
  router.push({ name: "user-settings", params: { id: props.id } });
}
</script>

<template>
  <div class="profile-view">
    <button @click="goToSettings">Edit Settings</button>
    <div v-if="isLoading">Loading...</div>
    <div v-else-if="userData">
      <h1>{{ userData.name }}</h1>
      <p>Email: {{ userData.email }}</p>
    </div>
  </div>
</template>
```

---

## Nested (Child) Routes & Layouts

Nested routes allow composing UI hierarchies where child routes render inside a parent component's `<RouterView />`:

```typescript
// src/router/routes.ts
const routes: RouteRecordRaw[] = [
  {
    path: "/dashboard",
    component: () => import("@/layouts/DashboardLayout.vue"),
    meta: { requiresAuth: true },
    children: [
      {
        path: "", // Default child route: /dashboard
        name: "dashboard-home",
        component: () => import("@/views/dashboard/OverviewView.vue"),
      },
      {
        path: "analytics", // Path: /dashboard/analytics
        name: "dashboard-analytics",
        component: () => import("@/views/dashboard/AnalyticsView.vue"),
      },
      {
        path: "settings", // Path: /dashboard/settings
        component: () => import("@/views/dashboard/SettingsLayout.vue"),
        children: [
          {
            path: "profile", // /dashboard/settings/profile
            name: "settings-profile",
            component: () => import("@/views/dashboard/settings/ProfileTab.vue"),
          },
          {
            path: "billing", // /dashboard/settings/billing
            name: "settings-billing",
            component: () => import("@/views/dashboard/settings/BillingTab.vue"),
          },
        ],
      },
    ],
  },
];
```

```vue
<!-- src/layouts/DashboardLayout.vue -->
<template>
  <div class="dashboard-shell">
    <aside class="sidebar">
      <nav>
        <RouterLink :to="{ name: 'dashboard-home' }">Overview</RouterLink>
        <RouterLink :to="{ name: 'dashboard-analytics' }">Analytics</RouterLink>
        <RouterLink :to="{ name: 'settings-profile' }">Settings</RouterLink>
      </nav>
    </aside>

    <main class="content-area">
      <!-- Child routes render here -->
      <RouterView v-slot="{ Component, route }">
        <Transition name="fade" mode="out-in">
          <component :is="Component" :key="route.path" />
        </Transition>
      </RouterView>
    </main>
  </div>
</template>
```

---

## Navigation Guards (Pipeline & Architecture)

Navigation guards control whether a navigation is allowed, redirected, or canceled.

```text
Navigation Flow:
1. Navigation triggered (e.g. router.push)
2. In-component `onBeforeRouteLeave`
3. Global `beforeEach` guards
4. In-component `onBeforeRouteUpdate` (if reusing component)
5. Route config `beforeEnter` guards
6. Resolve async route components
7. In-component `beforeRouteEnter`
8. Global `beforeResolve` guards
9. Navigation confirmed
10. Global `afterEach` hooks
11. DOM updates triggered
```

### Complete Authentication & Role Guard System

```typescript
// src/router/guards.ts
import type { Router } from "vue-router";
import { useAuthStore } from "@/stores/auth";

export function setupNavigationGuards(router: Router) {
  // Global beforeEach: Auth & Permission Check
  router.beforeEach(async (to, from) => {
    const authStore = useAuthStore();

    // 1. Dynamic Page Title
    const baseTitle = "Enterprise App";
    document.title = to.meta.title ? `${to.meta.title} | ${baseTitle}` : baseTitle;

    // 2. Check if route requires authentication
    if (to.meta.requiresAuth) {
      if (!authStore.isAuthenticated) {
        // Redirect to login page and preserve target destination in redirect query
        return {
          name: "login",
          query: { redirect: to.fullPath },
        };
      }

      // 3. Role-Based Access Control (RBAC)
      const requiredRoles = to.meta.roles as string[] | undefined;
      if (requiredRoles && requiredRoles.length > 0) {
        const hasRole = requiredRoles.some((role) => authStore.userRoles.includes(role));
        if (!hasRole) {
          // User is authenticated but lacks permission
          return { name: "forbidden" };
        }
      }
    }

    // 4. Prevent authenticated users from visiting /login or /register
    if (to.meta.guestOnly && authStore.isAuthenticated) {
      return { name: "dashboard-home" };
    }

    // Allow navigation
    return true;
  });

  // Global afterEach: Analytics & Progress Bar completion
  router.afterEach((to, from, failure) => {
    if (!failure) {
      // Send pageview event to analytics
      if (typeof window !== "undefined" && (window as any).gtag) {
        (window as any).gtag("config", "GA_MEASUREMENT_ID", {
          page_path: to.fullPath,
        });
      }
    }
  });
}
```

---

## Programmatic Navigation Cheatsheet

```typescript
import { useRouter } from "vue-router";

const router = useRouter();

// 1. Navigate by path
router.push("/users/42");

// 2. Navigate by named route with params & query params
router.push({
  name: "project-detail",
  params: { orgId: "acme", projectId: "123" },
  query: { view: "kanban", page: "1" },
  hash: "#task-456",
});

// 3. Replace current history entry (no back button entry)
router.replace({ name: "login" });

// 4. Step forward/backward in history
router.go(-1); // Back
router.go(1);  // Forward
```

---

## Troubleshooting & Common Gotchas

1. **Parameters change but component does not update**
   When navigating between `/users/1` and `/users/2`, Vue reuses the mounted component instance for efficiency without triggering `onMounted`. Use `onBeforeRouteUpdate` or `:key="route.fullPath"` on `<RouterView />`.

2. **Infinite redirect loops in `beforeEach`**
   Always check if the user is *already* on the destination page before redirecting:

   ```typescript
   // ❌ WRONG: Infinite loop
   router.beforeEach((to) => {
     if (!isAuth) return '/login'; // Will re-enter beforeEach for /login!
   });

   // ✅ CORRECT:
   router.beforeEach((to) => {
     if (!isAuth && to.name !== 'login') return { name: 'login' };
   });
   ```

3. **Missing Catch-All Route**
   Always define `/:pathMatch(.*)*` at the bottom of your routes array to catch 404s gracefully.
