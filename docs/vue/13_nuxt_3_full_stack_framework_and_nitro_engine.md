# Module 13: Nuxt 3 — Full-Stack Framework & Nitro Engine

**Track:** Vue — Progressive Web Framework  
**Category:** Full-Stack & Server-Side Rendering (SSR)

---

## What Is Nuxt 3?

**Nuxt 3** is an intuitive, full-stack open-source framework built on Vue 3, Vite, and the **Nitro** server engine. It transforms Vue from a client-side view library into a complete universal web application platform capable of:

1. **Server-Side Rendering (SSR)**: Instant First Contentful Paint (FCP) and optimal SEO.
2. **Hybrid Rendering & Incremental Static Regeneration (ISR)**: Per-route caching and pre-rendering rules.
3. **Automated Directory-Based Routing**: Zero boilerplate file-system routing.
4. **Auto-Imports**: Automatic importing of components, composables, and Vue/Nuxt APIs.
5. **Universal Nitro Engine**: Deploy anywhere without code changes (Node.js, Docker, Cloudflare Workers, Vercel, Deno, AWS Lambda).

---

## The Nitro Server Engine & H3 Architecture

At the core of Nuxt 3 is **Nitro**, an ultrafast, lightweight server engine powered by **H3** (a composable, minimal HTTP framework).

```
┌────────────────────────────────────────────────────────┐
│                      Client / Browser                  │
└──────────────────────────┬─────────────────────────────┘
                           │ HTTP Request
                           ▼
┌────────────────────────────────────────────────────────┐
│                   Nitro Engine (H3)                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │   Route Rules (SWR / ISR / Static / SSR / CORS)  │  │
│  └───────────────────────┬──────────────────────────┘  │
│                          ▼                             │
│  ┌───────────────────────┴──────────────────────────┐  │
│  │   Server API Routes (server/api/ & server/routes)│  │
│  └───────────────────────┬──────────────────────────┘  │
│                          ▼                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │   Vue 3 SSR Engine (Render App to HTML + State)  │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────┬─────────────────────────────┘
                           │ HTML Stream / JSON Payload
                           ▼
┌────────────────────────────────────────────────────────┐
│                      Browser Hydration                 │
└────────────────────────────────────────────────────────┘
```

---

## Scaffolding a Nuxt 3 Project

```bash
# Initialize a new Nuxt 3 project
npx nuxi@latest init my-nuxt-app

cd my-nuxt-app
npm install
npm run dev
```

### Standard Nuxt 3 Project Structure

```
my-nuxt-app/
├── .nuxt/                  ← Auto-generated build artifacts & TypeScript types
├── assets/                 ← Uncompiled assets (SASS, LESS, raw images)
├── components/             ← Auto-imported Vue components
├── composables/            ← Auto-imported Composition API functions
├── layouts/                ← Reusable multi-page layouts
├── middleware/             ← Route navigation middleware
├── pages/                  ← File-based routing (triggers vue-router)
├── plugins/                ← Nuxt plugins (executed before app mount)
├── public/                 ← Static files served directly at root /
├── server/                 ← Nitro server engine code
│   ├── api/                ← Server endpoints (prefixed with /api)
│   ├── routes/             ← Custom server routes
│   ├── middleware/         ← Server-side request interceptors
│   └── utils/              ← Server-side shared helpers
├── app.vue                 ← Main application entry component
├── nuxt.config.ts          ← Master configuration
├── app.config.ts           ← Runtime public configuration
└── package.json
```

---

## Master Configuration: `nuxt.config.ts`

```typescript
// nuxt.config.ts
export default defineNuxtConfig({
  // Enable TypeScript strict checking
  typescript: {
    strict: true,
    typeCheck: true,
  },

  // Modules ecosystem
  modules: [
    "@pinia/nuxt",
    "@vueuse/nuxt",
    "@nuxtjs/tailwindcss",
  ],

  // Global CSS
  css: ["@/assets/css/main.css"],

  // Route Rules & Hybrid Rendering Configuration
  routeRules: {
    // Homepage pre-rendered at build time (SSG)
    "/": { prerender: true },
    // Product pages cached with SWR (Stale-While-Revalidate) for 1 hour
    "/products/**": { swr: 3600 },
    // Admin dashboard: Client-side Single Page App only (No SSR overhead)
    "/admin/**": { ssr: false },
    // API reverse proxy to internal microservice
    "/api/v1/legacy/**": { proxy: "http://backend-cluster.internal:8000/**" },
    // Automatic redirect rule
    "/old-docs/**": { redirect: "/docs" },
    // CORS headers on public API
    "/api/public/**": { cors: true },
  },

  // Environment variables and runtime configuration
  runtimeConfig: {
    // Private server-only secrets (never exposed to client bundle)
    databaseUrl: process.env.DATABASE_URL || "postgres://localhost:5432/app",
    jwtSecret: process.env.JWT_SECRET || "default-dev-secret",
    
    // Public keys exposed to both server and browser
    public: {
      apiBaseUrl: process.env.NUXT_PUBLIC_API_BASE || "https://api.example.com",
      environment: process.env.NODE_ENV || "development",
    },
  },

  // Nitro server deployment presets
  nitro: {
    preset: "node-server", // Options: 'cloudflare-pages', 'vercel', 'deno-server', 'aws-lambda'
    compressPublicAssets: true,
  },

  devtools: { enabled: true },
});
```

---

## Server API Routes with H3

Every file in `server/api/` automatically generates a RESTful backend endpoint:

### 1. GET Endpoint with Query Parsing

```typescript
// server/api/products/index.get.ts
import { defineEventHandler, getQuery, createError } from "h3";

export default defineEventHandler(async (event) => {
  const query = getQuery(event);
  const category = query.category as string | undefined;
  const limit = Math.min(Number(query.limit) || 20, 100);

  // Access server-only runtime secrets
  const config = useRuntimeConfig(event);

  try {
    // Perform database or backend query
    const products = await fetchFromDatabase(category, limit, config.databaseUrl);
    return { success: true, count: products.length, data: products };
  } catch (error) {
    throw createError({
      statusCode: 500,
      statusMessage: "Internal Server Error",
      data: { details: (error as Error).message },
    });
  }
});

async function fetchFromDatabase(category?: string, limit = 20, _dbUrl?: string) {
  return [
    { id: "p1", title: "Mechanical Keyboard", price: 149.99, category: "electronics" },
    { id: "p2", title: "Ergonomic Chair", price: 399.00, category: "furniture" },
  ];
}
```

### 2. POST Endpoint with Body Validation

```typescript
// server/api/products/create.post.ts
import { defineEventHandler, readBody, createError } from "h3";
import { z } from "zod";

const CreateProductSchema = z.object({
  title: z.string().min(3),
  price: z.number().positive(),
  category: z.string(),
});

export default defineEventHandler(async (event) => {
  const body = await readBody(event);

  const parseResult = CreateProductSchema.safeParse(body);
  if (!parseResult.success) {
    throw createError({
      statusCode: 400,
      statusMessage: "Invalid Product Payload",
      data: parseResult.error.flatten(),
    });
  }

  const newProduct = {
    id: `prod_${Date.now()}`,
    ...parseResult.data,
    createdAt: new Date().toISOString(),
  };

  // Set HTTP Status Code
  setResponseStatus(event, 201);
  return { success: true, product: newProduct };
});
```

---

## Server Middleware

Files in `server/middleware/` run on **every** incoming HTTP request before passing to route handlers:

```typescript
// server/middleware/auth.ts
import { defineEventHandler, getHeader, createError } from "h3";

export default defineEventHandler((event) => {
  const url = getRequestURL(event);

  // Only protect /api/protected/* routes
  if (url.pathname.startsWith("/api/protected")) {
    const authHeader = getHeader(event, "authorization");

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      throw createError({
        statusCode: 401,
        statusMessage: "Unauthorized: Missing Bearer Token",
      });
    }

    const token = authHeader.substring(7);
    if (token !== "valid-secret-token") {
      throw createError({
        statusCode: 403,
        statusMessage: "Forbidden: Invalid Token",
      });
    }

    // Attach decoded user info to the event context
    event.context.user = { id: "user_123", role: "admin" };
  }
});
```

---

## Universal Layouts & Pages

```vue
<!-- layouts/default.vue -->
<template>
  <div class="site-layout">
    <header class="navbar">
      <NuxtLink to="/">Home</NuxtLink>
      <NuxtLink to="/products">Products</NuxtLink>
      <NuxtLink to="/admin">Admin</NuxtLink>
    </header>

    <main class="page-content">
      <slot />
    </main>

    <footer class="footer">
      <p>© {{ new Date().getFullYear() }} Full-Stack Nuxt App</p>
    </footer>
  </div>
</template>
```

```vue
<!-- pages/index.vue -->
<script setup lang="ts">
// Page Metadata (SEO)
useHead({
  title: "Welcome to Our Platform",
  meta: [
    { name: "description", content: "High-performance Nuxt 3 Full-Stack Application" },
  ],
});
</script>

<template>
  <div class="hero">
    <h1>Lightning Fast Universal Web App</h1>
    <NuxtLink to="/products" class="btn-cta">Explore Products</NuxtLink>
  </div>
</template>
```

---

## Production Deployment Targets with Nitro

Deploying Nuxt to different clouds requires changing just one environment variable or config flag:

```bash
# 1. Standard Node.js Production Server
NITRO_PRESET=node-server npm run build
node .output/server/index.mjs

# 2. Cloudflare Pages / Workers (Edge)
NITRO_PRESET=cloudflare-pages npm run build

# 3. Vercel Serverless
NITRO_PRESET=vercel npm run build

# 4. AWS Lambda
NITRO_PRESET=aws-lambda npm run build
```

---

## Troubleshooting & Best Practices

1. **Avoid leaking server secrets to the client**
   Never put database passwords or private API keys inside `runtimeConfig.public`. Only place them at the top level of `runtimeConfig`.

2. **Window / DOM access in SSR**
   Accessing `window`, `document`, or `localStorage` directly in component setup functions crashes the server with `ReferenceError: window is not defined`. Wrap them in `onMounted()` or check `if (import.meta.client)`.

3. **Hydration Mismatch Errors**
   Ensure server-rendered HTML matches the initial client render. Differences in timestamps (`new Date()`) or client-only flags before mounting cause Vue hydration mismatches. Use `<ClientOnly>` component wrappers when necessary.
