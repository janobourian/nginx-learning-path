# Module 10: Declaration Files (`.d.ts`), Ambient Namespaces & Global Augmentation

**Track:** TypeScript — Enterprise Type System
**Category:** Type Definitions, Interop & Library Publishing

---

## 1. What Are Declaration Files (`.d.ts`)?

A **Declaration File** (with the `.d.ts` extension) contains **only type metadata** and zero executable JavaScript implementation code.

Declaration files serve two primary roles in the TypeScript ecosystem:

1. **Providing Type Definitions for Untyped JavaScript**: Describing the shapes of npm packages, legacy scripts, or browser global APIs written in plain JavaScript.
2. **Library Output Artifacts**: When you publish a TypeScript library with `"declaration": true`, `tsc` generates `.d.ts` files alongside `.js` files so consumers get complete type definitions without needing your original `.ts` source files.

---

## 2. Ambient Declarations (`declare` keyword)

The `declare` keyword tells the TypeScript compiler: *"This identifier exists in the global runtime environment (provided by the browser, Node.js runtime, or an external script tag), so do not complain about missing declarations."*

```typescript
// types/ambient-globals.d.ts

// 1. Ambient Variable (e.g. injected by CDN script)
declare const GA_TRACKING_ID: string;

// 2. Ambient Function
declare function initializeAnalytics(apiKey: string, debug?: boolean): void;

// 3. Ambient Class
declare class PaymentGatewayClient {
  constructor(apiKey: string);
  charge(amount: number): Promise<boolean>;
}

// 4. Ambient Enum
declare enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  ERROR = 2,
}
```

---

## 3. Global Augmentation (`declare global`)

In TypeScript files that contain `import` or `export` statements (which makes them ES modules), top-level declarations are scoped locally to that module.

To add or augment types in the **global scope** (such as `window`, `process.env`, or `NodeJS.Process`), use the `declare global` block:

```typescript
// src/types/global-extensions.d.ts

// Augment the browser Window interface
declare global {
  interface Window {
    __APP_VERSION__: string;
    ethereum?: {
      isMetaMask: boolean;
      request: (args: { method: string; params?: any[] }) => Promise<any>;
    };
  }

  // Augment Node.js process.env environment variables
  namespace NodeJS {
    interface ProcessEnv {
      NODE_ENV: "development" | "production" | "test";
      PORT: string;
      DATABASE_URL: string;
      JWT_SECRET: string;
      ENABLE_FEATURE_FLAGS?: "true" | "false";
    }
  }
}

// Ensure this file is treated as a module:
export {};
```

Now, across your entire project, `window.__APP_VERSION__` and `process.env.DATABASE_URL` are strictly typed with full autocomplete!

---

## 4. Ambient Module Declarations (`declare module`)

When consuming a third-party npm package that does not provide TypeScript definitions and has no `@types/` package on DefinitelyTyped, you can declare the module signature yourself:

```typescript
// src/types/third-party.d.ts

// 1. Full Module Signature
declare module "legacy-chart-engine" {
  export interface ChartOptions {
    theme?: "dark" | "light";
    responsive?: boolean;
  }

  export class Chart {
    constructor(canvasId: string, options?: ChartOptions);
    render(data: number[]): void;
    destroy(): void;
  }

  export function getVersion(): string;
  export default Chart;
}

// 2. Wildcard Module Declarations (for Non-JS Asset Imports)
declare module "*.svg" {
  const content: string;
  export default content;
}

declare module "*.png" {
  const src: string;
  export default src;
}

declare module "*.module.css" {
  const classes: Record<string, string>;
  export default classes;
}
```

Now you can write:

```typescript
import Chart, { getVersion } from "legacy-chart-engine";
import logoUrl from "./assets/logo.svg";
import styles from "./Header.module.css";
```

---

## 5. Module Augmentation (Extending Existing Libraries)

You can augment types in external npm packages to reflect plugins or custom middleware:

```typescript
// src/types/express-augmentation.d.ts
import "express";

// Augment Express Request interface with authenticated user session
declare module "express" {
  export interface Request {
    user?: {
      id: string;
      email: string;
      role: "admin" | "member";
    };
    correlationId: string;
  }
}
```

---

## 6. Triple-Slash Directives (`/// <reference ... />`)

Triple-slash directives are single-line comments containing an XML tag used as compiler directives at the top of a file:

```typescript
// 1. Reference type declarations from @types or node_modules
/// <reference types="vite/client" />
/// <reference types="node" />

// 2. Reference another local declaration file
/// <reference path="./custom-ambient-types.d.ts" />
```

In modern TypeScript projects, `compilerOptions.types` in `tsconfig.json` is preferred over triple-slash directives, but they remain standard in build tool declaration headers (e.g. `vite-env.d.ts`).

---

## 7. Publishing Typed npm Packages

When publishing an npm package with TypeScript definitions, configure your `package.json` to point to both the compiled JavaScript files and the generated `.d.ts` declaration files:

```json
{
  "name": "@my-org/core-toolkit",
  "version": "1.0.0",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "require": "./dist/index.cjs"
    }
  },
  "scripts": {
    "build": "tsc --project tsconfig.build.json"
  },
  "files": [
    "dist"
  ]
}
```

---

## Troubleshooting & Best Practices

1. **`.d.ts` files containing executable code**
   Declaration files must **never** contain executable code, function bodies, or variable initializations (`const x = 5;`). They should only contain types, interfaces, and `declare` statements.

2. **Declaration file not picked up by compiler**
   Ensure your `.d.ts` directory is included in `tsconfig.json` under `"include": ["src/**/*", "types/**/*"]`.

3. **Accidental Global Pollution**
   If a `.d.ts` file does not contain any `import` or `export` statement, all declarations inside it automatically become **global**. Add `export {};` at the bottom if you only want the file to declare ambient modules without polluting the global namespace.
