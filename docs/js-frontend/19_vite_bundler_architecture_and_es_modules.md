# Module 19: Vite Architecture, Native ES Modules & Production Bundling

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** Build Tooling, Bundler Architecture & Hot Module Replacement (HMR)

---

## 1. Why Vite Revolutionized Frontend Tooling (Vite vs Webpack)

In legacy bundlers (Webpack, Parcel, Rollup in dev):
- The bundler had to crawl, parse, and bundle your entire codebase into large bundles **before the dev server could even start**.
- In apps with 5,000 modules, dev server cold start took **30 to 90 seconds**, and saving a file caused a **3 to 5 second lag**.

**Vite (French for "Fast")** completely reimagined this architecture:
1. **Unbundled Dev Server over Native ESM**: The browser requests modules on-demand as standard `<script type="module">`. The dev server starts **instantly in < 100ms** regardless of project size!
2. **Dependency Pre-Bundling with Esbuild**: Compiles npm CommonJS/UMD dependencies to ESM using **Esbuild (written in Go, 50x faster than JS-based bundlers)**.
3. **Optimized Production Bundles**: Uses **Rollup / Rolldown** for tree-shaking, chunk splitting, and asset hashing.

```
Development Server Comparison:

Webpack (Bundled Dev Server):
[5,000 Source Modules] ──► [Bundle All Files (30s+)] ──► [Dev Server Ready]

Vite (Unbundled Native ESM Dev Server):
[Dev Server Ready (<100ms!)] ◄── Browser requests only the active visible page modules via HTTP/2!
```

---

## 2. Dynamic Code Splitting with `import()`

Never bundle your entire application into a single massive 5MB `index.js` file.

Use **Dynamic Imports (`import()`)** to split routes and heavy third-party libraries into independent, lazy-loaded chunks:

```javascript
// src/router.js
const routes = {
  '/': () => import('./views/HomeView.js'),
  '/dashboard': () => import('./views/DashboardView.js'), // ◄── Separate chunk!
  '/analytics': () => import('./views/AnalyticsView.js'), // ◄── Separate chunk!
};

export async function navigateTo(path) {
  const loader = routes[path] || routes['/'];
  // The browser downloads analytics.chunk.js ONLY when the user visits /analytics!
  const module = await loader();
  const ViewClass = module.default;
  new ViewClass().render();
}
```

---

## 3. Hot Module Replacement (HMR) API

Vite provides native **Hot Module Replacement (HMR)** through `import.meta.hot`, allowing you to update module code in real-time **without reloading the browser tab or losing UI state**:

```javascript
// src/components/counter.js
let count = 0;

export function initCounter(element) {
  element.innerHTML = `<button id="count-btn">Count is ${count}</button>`;
  element.querySelector('#count-btn').addEventListener('click', () => {
    count++;
    element.querySelector('#count-btn').textContent = `Count is ${count}`;
  });
}

// ◄── VITE HMR HOOK ──►
if (import.meta.hot) {
  // Accept updates to this module without full page refresh:
  import.meta.hot.accept((newModule) => {
    console.log('[HMR]: Hot-swapping counter module...');
    // Re-initialize UI while retaining 'count' variable:
    newModule.initCounter(document.querySelector('#counter-container'));
  });

  // Cleanup hook before module is replaced:
  import.meta.hot.dispose(() => {
    console.log('[HMR]: Cleaning up old module side effects.');
  });
}
```

---

## 4. Custom Vite Plugin Architecture

Vite plugins extend Rollup's plugin interface with Vite-specific dev hooks:

```javascript
// plugins/vite-markdown-plugin.js
export function markdownPlugin() {
  return {
    name: 'vite-plugin-markdown',
    // 1. Transform markdown files to JavaScript modules:
    transform(src, id) {
      if (id.endsWith('.md')) {
        // Convert Markdown text to exported JS string:
        const escaped = JSON.stringify(src);
        return {
          code: `export default ${escaped};`,
          map: null, // Source map
        };
      }
    },
    // 2. Custom Hot Update Handler:
    handleHotUpdate({ file, server }) {
      if (file.endsWith('.md')) {
        console.log(`[Plugin]: Markdown file updated: ${file}`);
        server.ws.send({ type: 'full-reload' });
      }
    },
  };
}
```

---

## 5. Enterprise Production Vite Configuration (`vite.config.js`)

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import path from 'node:path';
import { markdownPlugin } from './plugins/vite-markdown-plugin.js';

export default defineConfig({
  plugins: [markdownPlugin()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    strictPort: true,
    cors: true,
  },
  build: {
    target: 'es2022', // Target modern browsers supporting top-level await
    outDir: 'dist',
    sourcemap: true,
    minify: 'esbuild', // Blazing fast minification
    cssCodeSplit: true,
    rollupOptions: {
      output: {
        // Granular Vendor Chunk Splitting:
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('lodash') || id.includes('date-fns')) {
              return 'vendor-utils';
            }
            if (id.includes('chart.js') || id.includes('three')) {
              return 'vendor-charts';
            }
            return 'vendor-core';
          }
        },
        chunkFileNames: 'assets/js/[name]-[hash].js',
        entryFileNames: 'assets/js/[name]-[hash].js',
        assetFileNames: 'assets/[ext]/[name]-[hash].[ext]',
      },
    },
  },
});
```

---

## Production Build & Bundling Checklist

- [ ] **Native ESM Target**: Set `build.target: 'es2022'` to emit modern JavaScript without legacy ES5 polyfill bloat.
- [ ] **Manual Vendor Chunking**: Split massive charting / 3D dependencies into separate chunks via `rollupOptions.output.manualChunks`.
- [ ] **Asset Hashing**: Ensure all production assets include content hashes (`[name]-[hash].js`) for immutable CDN caching (`Cache-Control: max-age=31536000, immutable`).
- [ ] **Tree-Shaking Verification**: Use `import { specificFn } from 'lib'` rather than `import * as lib` to enable Rollup dead-code elimination.
- [ ] **Audit Bundle Sizes**: Use `rollup-plugin-visualizer` to visualize bundle composition and prevent accidental package bloat.
