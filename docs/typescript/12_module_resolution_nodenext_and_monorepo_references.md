# Module 12: Module Resolution (`NodeNext`), ESM/CJS Dual Packages & Project References

**Track:** TypeScript — Enterprise Type System  
**Category:** Module Systems, Monorepos & Build Graph Optimization

---

## 1. The Module Resolution Landscape

Module resolution is the process the TypeScript compiler uses to determine what a file or identifier `import { x } from "module-specifier"` actually points to on disk.

Historically, the ecosystem had fragmented resolution algorithms. TypeScript modernizes this with dedicated `moduleResolution` settings:

| `moduleResolution` | Target Environment | Key Characteristics |
| :--- | :--- | :--- |
| **`NodeNext` / `Node16`** | **Modern Node.js (v18+)** | Strictly enforces ECMAScript Modules (ESM) rules, `package.json` `"exports"` fields, and mandatory file extensions (`.js`). |
| **`Bundler`** | **Vite, esbuild, Webpack 5** | Emulates bundler resolution: allows extensionless imports, path aliases, and non-strict package exports. |
| **`Node10` (Legacy)** | Old CommonJS Node | Resolves `index.js` and extensionless relative paths. Obsolete for modern packages. |
| **`Classic`** | Pre-TypeScript 1.6 | Legacy fallback. Do not use. |

---

## 2. `NodeNext` Resolution & Mandatory File Extensions

In pure ECMAScript Modules under `NodeNext`:
1. Every relative import **must specify its output file extension** (`.js`, `.mjs`, or `.cjs`), even when authoring in TypeScript!
2. TypeScript does **not** rewrite `.ts` to `.js` during compilation; therefore, you import `./utils.js`, which points to `./utils.ts` during compilation and `./utils.js` at runtime.

```typescript
// src/services/auth.ts

// ✅ CORRECT under "moduleResolution": "NodeNext":
import { hashPassword } from "../utils/crypto.js"; // Points to ../utils/crypto.ts during type check!
import type { DatabaseConfig } from "../config/db.js";

// ❌ WRONG under "NodeNext" (Throws TS2835: Relative import paths need explicit file extensions):
// import { hashPassword } from "../utils/crypto";
```

### File Extension Matrix for ESM/CommonJS Dual Support

| Source File | Compiles To (JS) | Declaration (.d.ts) | Module Format |
| :--- | :--- | :--- | :--- |
| `.ts` | Matches `package.json` `"type"` | `.d.ts` | Context-dependent |
| **`.mts`** | **`.mjs`** (Always ESM) | **`.d.mts`** | Strict ECMAScript Module |
| **`.cts`** | **`.cjs`** (Always CommonJS) | **`.d.cts`** | Strict CommonJS Module |

---

## 3. Authoring Dual ESM / CommonJS npm Packages

In modern enterprise libraries, your package must support both ESM consumers (`import`) and legacy CommonJS consumers (`require()`) seamlessly using the `package.json` `"exports"` map:

```json
{
  "name": "@acme/core-sdk",
  "version": "2.0.0",
  "type": "module",
  "exports": {
    ".": {
      "types": {
        "import": "./dist/esm/index.d.ts",
        "require": "./dist/cjs/index.d.cts"
      },
      "import": "./dist/esm/index.js",
      "require": "./dist/cjs/index.cjs"
    },
    "./submodule": {
      "types": "./dist/esm/submodule.d.ts",
      "import": "./dist/esm/submodule.js"
    }
  },
  "scripts": {
    "build:esm": "tsc -p tsconfig.esm.json",
    "build:cjs": "tsc -p tsconfig.cjs.json",
    "build": "npm run build:esm && npm run build:cjs"
  }
}
```

```json
// tsconfig.esm.json
{
  "extends": "./tsconfig.base.json",
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist/esm",
    "declaration": true
  }
}
```

---

## 4. TypeScript Project References (`composite: true`)

In large monorepos containing dozens of packages, running `tsc` across all source files at once causes massive memory consumption and slow build times.

**Project References** allow partitioning a monorepo into independent, modular compilation units with explicit dependencies.

```
Monorepo Architecture Graph:
        ┌─────────────┐
        │  apps/web   │
        └──────┬──────┘
               │ depends on
               ▼
        ┌─────────────┐
        │ packages/ui │
        └──────┬──────┘
               │ depends on
               ▼
        ┌─────────────┐
        │packages/core│
        └─────────────┘
```

### Benefits of Project References:
1. **Topological Incremental Compilation**: Packages are built in dependency order.
2. **Build Cache Isolation**: If `packages/core` hasn't changed, `tsc --build` skips it entirely using its `.tsbuildinfo` cache.
3. **Strict Architecture Enforcement**: `apps/web` cannot import private internals of `packages/core` unless declared in `references`.

---

## 5. Setting Up a Composite Monorepo

### 1. Leaf Package: `packages/core/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "rootDir": "./src",
    "outDir": "./dist",
    "composite": true,                     /* Mandatory for Project References */
    "declaration": true,                   /* Mandatory for composite projects */
    "declarationMap": true,                /* Maps .d.ts back to source .ts for IDE navigation */
    "incremental": true
  },
  "include": ["src/**/*"]
}
```

### 2. Dependent Package: `packages/ui/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "rootDir": "./src",
    "outDir": "./dist",
    "composite": true,
    "declaration": true,
    "declarationMap": true
  },
  "references": [
    { "path": "../core" }                  /* Explicit reference to core dependency */
  ],
  "include": ["src/**/*"]
}
```

### 3. Root Orchestrator: `tsconfig.json`

```json
{
  "files": [],
  "references": [
    { "path": "./packages/core" },
    { "path": "./packages/ui" },
    { "path": "./apps/web" }
  ]
}
```

---

## 6. Monorepo Build Execution: `tsc --build` (`tsc -b`)

To build the entire monorepo in topological order with incremental caching:

```bash
# Build entire dependency graph
npx tsc --build --verbose

# Force clean and rebuild all packages
npx tsc --build --clean
npx tsc --build --force

# Watch mode across the entire monorepo
npx tsc --build --watch
```

Output:
```
[12:00:01] Projects in this build: 
    * packages/core/tsconfig.json
    * packages/ui/tsconfig.json
    * apps/web/tsconfig.json

[12:00:02] Building project 'packages/core/tsconfig.json'...
[12:00:03] Building project 'packages/ui/tsconfig.json'...
[12:00:04] Building project 'apps/web/tsconfig.json'...
[12:00:04] Build completed successfully in 2.1s.
```

---

## Troubleshooting & Best Practices

1. **`TS6305: Output file has not been built from project`**
   - This occurs when `packages/ui` imports from `packages/core`, but `packages/core` has not yet been built to generate its `.d.ts` declaration files.
   - Always compile with `tsc --build` rather than `tsc` so TypeScript builds upstream dependencies first.

2. **Package.json `"exports"` order matters!**
   In `"exports"`, always put `"types"` **first**, before `"import"` and `"require"`, so TypeScript resolves type definitions before falling back to JavaScript targets.
