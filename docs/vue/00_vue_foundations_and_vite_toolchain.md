# Module 00: Vue Foundations & Vite Toolchain

**Track:** Vue — Progressive Web Framework
**Category:** Getting Started & Build System

---

## What Is Vue?

Vue.js is a JavaScript framework for building user interfaces. Conceived by Evan You in 2014, it is designed to be incrementally adoptable: you can drop a script tag into an existing page to add interactivity to one widget, or you can build a full-scale single-page application with Vue Router, Pinia, and a Vite build pipeline.

Vue 3 (released September 2020) introduced the **Composition API** — a more flexible way to organize component logic using functions rather than the Options API's object structure. Both APIs are supported and can coexist in the same project.

Vue is **reactive by default**: when data changes, the DOM updates automatically. You describe what the UI should look like given a certain state, and Vue ensures the DOM matches that description.

---

## Creating a Vue Project with Vite

Vite (French for "fast") is the official build tool for Vue projects. It uses native ES modules during development (no bundling — the browser imports each file directly) and Rollup for optimized production builds.

```bash

# Create a new Vue project (interactive)
npm create vue@latest

# Or create non-interactively with all features
npm create vue@latest my-app -- \
  --typescript \
  --router \
  --pinia \
  --vitest \
  --eslint \
  --prettier

cd my-app
npm install
npm run dev
```

The `create vue` scaffolder generates:

```text
my-app/
├── src/
│   ├── assets/           ← Static assets (fonts, images, global CSS)
│   ├── components/       ← Reusable Vue components
│   ├── composables/      ← Reusable Composition API functions
│   ├── router/
│   │   └── index.ts      ← Vue Router configuration
│   ├── stores/           ← Pinia stores
│   ├── views/            ← Page-level components (routed to)
│   ├── App.vue           ← Root component
│   └── main.ts           ← Application entry point
├── public/               ← Files served as-is (favicon, robots.txt)
├── index.html            ← Vite's entry point HTML
├── vite.config.ts        ← Vite configuration
├── tsconfig.json         ← TypeScript configuration
└── package.json
```

---

## The Application Entry Point

```typescript
// src/main.ts
import { createApp } from "vue";
import { createPinia } from "pinia";
import router from "./router";
import App from "./App.vue";

// Import global CSS
import "./assets/main.css";

const app = createApp(App);

app.use(createPinia());  // State management
app.use(router);         // Client-side routing

app.mount("#app");       // Mount to <div id="app"> in index.html
```

```html
<!-- index.html -->
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>My Vue App</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
```

---

## Vite Configuration

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  plugins: [vue()],

  resolve: {
    alias: {
      // Allow imports like: import Button from "@/components/Button.vue"
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },

  server: {
    port: 3000,
    // Proxy API requests to avoid CORS in development
    proxy: {
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ""),
      },
    },
  },

  build: {
    outDir: "dist",
    sourcemap: true,

    rollupOptions: {
      output: {
        // Code splitting: vendor libraries in a separate chunk
        manualChunks: {
          vendor: ["vue", "vue-router", "pinia"],
        },
      },
    },
  },

  // Environment variables (prefix VITE_ to expose to client code)
  envPrefix: "VITE_",
});
```

Environment variables in `.env`:

```text
VITE_API_URL=https://api.example.com
VITE_APP_NAME=My App
```

Access in code:

```typescript
const apiUrl = import.meta.env.VITE_API_URL;
const isDev  = import.meta.env.DEV;    // true in development
const isProd = import.meta.env.PROD;   // true in production
```

---

## Your First Single File Component (SFC)

Vue components live in `.vue` files, which combine HTML template, TypeScript logic, and CSS styles in a single file:

```vue
<!-- src/components/Greeter.vue -->
<script setup lang="ts">
import { ref, computed } from "vue";

// Props: inputs from the parent component
interface Props {
  initialName?: string;
}
const props = withDefaults(defineProps<Props>(), {
  initialName: "World",
});

// Emits: events sent to the parent
const emit = defineEmits<{
  greet: [name: string, timestamp: number];
}>();

// Reactive state
const name = ref(props.initialName);
const count = ref(0);

// Computed property: re-evaluates only when `name` changes
const greeting = computed(() => `Hello, ${name.value}!`);

// Methods
function greet() {
  count.value++;
  emit("greet", name.value, Date.now());
}
</script>

<template>
  <div class="greeter">
    <h2>{{ greeting }}</h2>
    <input
      v-model="name"
      type="text"
      placeholder="Enter your name"
      class="greeter__input"
    />
    <button
      @click="greet"
      class="greeter__button"
    >
      Say Hello ({{ count }} times)
    </button>
  </div>
</template>

<style scoped>
/* scoped: styles only apply to THIS component */
.greeter {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  max-width: 400px;
}

.greeter__input {
  padding: 0.5rem;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 1rem;
}

.greeter__button {
  padding: 0.5rem 1rem;
  background-color: #42b883;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1rem;
}

.greeter__button:hover {
  background-color: #33a06f;
}
</style>
```

Use it in another component:

```vue
<!-- src/App.vue -->
<script setup lang="ts">
import Greeter from "@/components/Greeter.vue";

function onGreet(name: string, timestamp: number) {
  console.log(`${name} greeted at ${new Date(timestamp).toISOString()}`);
}
</script>

<template>
  <main>
    <Greeter initial-name="Vue" @greet="onGreet" />
  </main>
</template>
```

---

## The `<script setup>` Syntax

`<script setup>` is Vue 3's recommended way to write component logic. It is syntactic sugar over the `setup()` function with significant improvements:

- Top-level variables and imports are automatically available in the template
- No need to return anything from `setup()`
- Better TypeScript inference
- Smaller compiled output

```vue
<script setup lang="ts">
// This import is automatically available in the template
import { ref } from "vue";
import ChildComponent from "./Child.vue";

// This ref is available as `count` in the template
const count = ref(0);

// This function is available as `increment` in the template
function increment() { count.value++; }
</script>

<template>
  <!-- ChildComponent is automatically registered (no components: {} needed) -->
  <ChildComponent />

  <!-- count and increment are directly available -->
  <button @click="increment">{{ count }}</button>
</template>
```

---

## NPM Scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc && vite build",
    "preview": "vite preview",
    "test": "vitest",
    "test:e2e": "playwright test",
    "lint": "eslint . --fix",
    "type-check": "vue-tsc --noEmit"
  }
}
```

```bash

# Development server with hot module replacement
npm run dev

# Type-check and build for production
npm run build

# Preview the production build locally
npm run preview

# Run unit tests
npm run test

# Lint and auto-fix code style
npm run lint
```

---

## TypeScript Configuration for Vue

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "jsx": "preserve",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "noEmit": true,
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src/**/*.ts", "src/**/*.d.ts", "src/**/*.tsx", "src/**/*.vue"],
  "exclude": ["node_modules", "dist"]
}
```

---

## Troubleshooting

### Vite dev server starts but the page is blank

Open the browser console. The most common cause is a JavaScript error in `main.ts` or `App.vue`. Check that `#app` exists in `index.html` and that `createApp().mount("#app")` is called.

### TypeScript errors for `.vue` imports

Add `/// <reference types="vite/client" />` to `src/vite-env.d.ts`. This declares the module type for `.vue` files and Vite environment variables.

### Hot Module Replacement (HMR) doesn't work — full page reload instead

HMR breaks if a component's `<script setup>` throws an error during reload. Check the terminal (Vite logs HMR errors) and fix the root cause. Also ensure you haven't added `@vite/plugin-legacy` without the HMR workaround it provides.
