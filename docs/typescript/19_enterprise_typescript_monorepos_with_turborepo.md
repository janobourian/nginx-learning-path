# Module 19: Enterprise TypeScript Monorepos with Turborepo

**Track:** TypeScript — Enterprise Type System
**Category:** Monorepo Orchestration, Remote Caching & Workspace Architecture

---

## 1. Why Monorepos in Enterprise TypeScript?

In large engineering organizations, managing multiple independent git repositories (polyrepo) creates severe synchronization friction:

- Shared UI components or API types must be published to npm, requiring version bumps, changelogs, and pull requests across multiple repositories.
- Breaking API changes cannot be refactored or verified atomically in a single pull request.
- Tooling, linters, TypeScript compiler options, and dependencies drift across repositories.

An **Enterprise Monorepo** consolidates multiple applications (`apps/`) and shared libraries (`packages/`) into a single repository managed with **pnpm workspaces** and orchestrated with **Turborepo**.

```text
Enterprise Monorepo Architecture:
my-enterprise-monorepo/
├── apps/
│   ├── web/                    ← Next.js / Vue Frontend
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── api/                    ← Node.js / Hono / Express Backend
│       ├── package.json
│       └── tsconfig.json
├── packages/
│   ├── ui/                     ← Shared Design System Components
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── shared-types/           ← Core Shared Data Contracts & Schemas
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── typescript-config/      ← Centralized Base tsconfig Presets
│   │   ├── package.json
│   │   ├── base.json
│   │   ├── nextjs.json
│   │   └── node.json
│   └── eslint-config/          ← Shared ESLint Configurations
├── pnpm-workspace.yaml         ← Workspace Definition
├── turbo.json                  ← Turborepo Pipeline & Caching Config
├── package.json                ← Root Scripts & Dependencies
└── tsconfig.json               ← Root Composite Configuration
```

---

## 2. Setting Up Workspace Management with `pnpm`

`pnpm` is the recommended package manager for enterprise monorepos due to its content-addressable storage (saving gigabytes of disk space) and strict dependency isolation.

```yaml

# pnpm-workspace.yaml
packages:

  - "apps/*"
  - "packages/*"
```

```json
// package.json (Root)
{
  "name": "enterprise-monorepo",
  "private": true,
  "scripts": {
    "build": "turbo run build",
    "dev": "turbo run dev",
    "lint": "turbo run lint",
    "type-check": "turbo run type-check",
    "test": "turbo run test",
    "clean": "turbo run clean && rm -rf node_modules"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "typescript": "^5.5.0",
    "prettier": "^3.3.0"
  },
  "packageManager": "pnpm@9.4.0"
}
```

---

## 3. Centralized Shared TypeScript Configs (`@repo/typescript-config`)

Instead of duplicating compiler flags across 20 packages, create a dedicated configuration package:

```json
// packages/typescript-config/package.json
{
  "name": "@repo/typescript-config",
  "version": "0.0.0",
  "private": true,
  "files": [
    "base.json",
    "node.json",
    "react.json"
  ]
}
```

```json
// packages/typescript-config/base.json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "skipLibCheck": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "isolatedModules": true
  }
}
```

```json
// packages/typescript-config/react.json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "extends": "./base.json",
  "compilerOptions": {
    "jsx": "react-jsx",
    "lib": ["DOM", "DOM.Iterable", "ES2022"]
  }
}
```

### Consuming the Base Config in an Application

```json
// apps/web/tsconfig.json
{
  "extends": "@repo/typescript-config/react.json",
  "compilerOptions": {
    "rootDir": "./src",
    "outDir": "./dist"
  },
  "include": ["src/**/*"]
}
```

---

## 4. Turborepo Orchestration & Pipeline (`turbo.json`)

**Turborepo** is a high-performance build system for JavaScript and TypeScript monorepos. It calculates the dependency graph of your packages and executes tasks in parallel with **multi-core scheduling and computation caching**.

```json
// turbo.json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],       /* '^build' means build upstream dependencies first */
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"]
    },
    "type-check": {
      "dependsOn": ["^build"],       /* Ensure declaration files exist before type checking */
      "outputs": []
    },
    "lint": {
      "dependsOn": [],
      "outputs": []
    },
    "test": {
      "dependsOn": ["build"],
      "outputs": ["coverage/**"],
      "inputs": ["src/**/*.tsx", "src/**/*.ts", "test/**/*.ts"]
    },
    "dev": {
      "cache": false,                /* Never cache live dev server tasks */
      "persistent": true
    }
  }
}
```

---

## 5. Remote Caching & CI/CD Acceleration

Turborepo's most transformative enterprise feature is **Remote Caching**:

- When Developer A builds `packages/ui` on their laptop, the build artifact hash is saved to the remote cache (Vercel or AWS S3).
- When Developer B (or the GitHub Actions CI runner) checks out the branch, Turborepo downloads the cached artifact in milliseconds instead of re-compiling from source!

```bash

# Link local monorepo to Remote Cache
npx turbo link

# Run cached build across the entire monorepo
npx turbo run build
```

Output:

```text
• Packages in scope: @repo/api, @repo/web, @repo/ui, @repo/shared-types
• Running build in 4 packages

@repo/shared-types:build: cache hit, replaying logs (12ms) ──► FULL TURBO!
@repo/ui:build: cache hit, replaying logs (15ms)           ──► FULL TURBO!
@repo/api:build: cache hit, replaying logs (18ms)          ──► FULL TURBO!
@repo/web:build: compiled in 1.4s

Tasks:    4 total, 3 cached (75% cache hit rate)
Time:     1.45s (Saved 28.5s with Remote Cache!)
```

---

## 6. Monorepo CI/CD Pipeline (Affected Filtering)

In CI/CD, you only want to test and build the packages that were **affected by the current pull request**, rather than building all 50 packages:

```yaml

# .github/workflows/ci.yml
name: Monorepo CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:

      - uses: actions/checkout@v4
        with:
          fetch-depth: 2 # Required for git diff comparison

      - uses: pnpm/action-setup@v3
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'

      - name: Install Dependencies
        run: pnpm install --frozen-lockfile

      # Turborepo Remote Cache authentication
      - name: Turbo Remote Cache
        run: npx turbo login --token=${{ secrets.TURBO_TOKEN }} && npx turbo link --repo=${{ secrets.TURBO_TEAM }}
        env:
          TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
          TURBO_TEAM: ${{ secrets.TURBO_TEAM }}

      # Only run type-check, lint, and test on modified packages and their dependents:
      - name: Run Checks on Affected Packages
        run: pnpm turbo run type-check lint test --filter=...[origin/main]

      - name: Build Affected Applications
        run: pnpm turbo run build --filter=...[origin/main]
```

---

## Troubleshooting & Best Practices

1. **Circular Workspace Dependencies**
   If `packages/ui` depends on `packages/shared-types` and `packages/shared-types` imports from `packages/ui`, Turborepo will fail with a circular dependency error. Keep packages in a strict directed acyclic graph (DAG).

2. **Internal Package Imports via `workspace:*`**
   In internal package manifests, specify internal dependencies using the `workspace:*` protocol:

   ```json
   {
     "dependencies": {
       "@repo/shared-types": "workspace:*"
     }
   }
   ```
