# Module 00: Installation, Toolchain & Deno CLI

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Getting Started & Development Environment

---

## What Is Deno?

Deno is a JavaScript and TypeScript runtime built in Rust, using the V8 engine (the same engine as Node.js and Chrome). It was created by Ryan Dahl — the original creator of Node.js — to address design decisions in Node.js that he considered mistakes: the `node_modules` folder, the lack of security isolation, the `package.json` manifest, and the absence of TypeScript support in the default runtime.

Deno runs TypeScript natively without a compilation step. You write `.ts` files and run them directly with `deno run` — there is no `tsc`, no `ts-node`, no build step for local development. The TypeScript compilation is embedded in the Deno binary itself.

Deno ships as a **single self-contained executable** (~100MB). It includes the runtime, TypeScript compiler, formatter, linter, test runner, documentation generator, REPL, and a bundler. No package manager installation, no separate tool installations.

---

## Installation

### macOS and Linux

```bash
# Official install script — downloads the latest release binary
curl -fsSL https://deno.land/install.sh | sh

# The binary is placed in ~/.deno/bin/deno
# Add to your PATH (add this line to ~/.bashrc, ~/.zshrc, or ~/.profile)
export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

# Verify installation
deno --version
```

Output:
```
deno 2.1.4 (stable, release, aarch64-apple-darwin)
v8 13.0.245.12
typescript 5.6.2
```

### Windows (PowerShell)

```powershell
# Using PowerShell
irm https://deno.land/install.ps1 | iex

# Or using Winget
winget install DenoLand.Deno

# Or using Chocolatey
choco install deno
```

### Version Management with `dvm`

```bash
# Install dvm (Deno Version Manager)
curl -fsSL https://deno.land/install.sh | sh

# Install a specific Deno version
deno upgrade --version 2.0.0

# Or use asdf
asdf plugin add deno
asdf install deno 2.1.4
asdf global deno 2.1.4
```

### Upgrading Deno

```bash
# Upgrade to the latest stable release
deno upgrade

# Upgrade to a specific version
deno upgrade --version 2.1.0

# Upgrade to canary (nightly builds — not for production)
deno upgrade --canary
```

---

## The Deno Runtime Architecture

```
┌─────────────────────────────────────────────────┐
│                   Your Code                     │
│              (.ts / .js / .jsx / .tsx)          │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│             Deno Runtime (Rust)                 │
│                                                 │
│  ┌─────────────┐  ┌──────────────┐              │
│  │ V8 Isolate  │  │  TypeScript  │              │
│  │ (JavaScript)│  │  Compiler    │              │
│  └──────┬──────┘  └──────────────┘              │
│         │                                       │
│  ┌──────▼──────────────────────────────────┐    │
│  │           Deno Core (ops layer)          │    │
│  │  I/O ops, network ops, file system ops  │    │
│  └──────┬──────────────────────────────────┘    │
│         │                                       │
│  ┌──────▼──────────────────────────────────┐    │
│  │         Tokio (async runtime)           │    │
│  │     (event loop, async I/O, tasks)      │    │
│  └──────┬──────────────────────────────────┘    │
│         │                                       │
│  ┌──────▼──────────────────────────────────┐    │
│  │         Operating System                │    │
│  │     (syscalls, file descriptors)        │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

**V8 Isolate**: Each Deno process runs one V8 isolate — a sandboxed JavaScript execution environment. The isolate has no access to the filesystem, network, or environment variables by default.

**Ops layer**: Communication between JavaScript (in V8) and the Rust runtime happens via serialized messages called "ops". When your TypeScript code calls `Deno.readTextFile()`, it sends an op message to the Rust side, which performs the actual syscall and returns the result.

**Tokio**: Deno uses Tokio, Rust's async runtime, as its event loop. This means Deno's async I/O is backed by Tokio's epoll/kqueue polling — the same approach as NGINX and Rust's most performant network services.

---

## Your First Deno Program

```typescript
// hello.ts
const name = "Deno";
const greeting = `Hello, ${name}!`;
console.log(greeting);
```

```bash
deno run hello.ts
# Output: Hello, Deno!
```

No `package.json`, no `node_modules`, no compilation step. TypeScript runs directly.

---

## The Deno CLI — Complete Command Reference

### `deno run` — Execute a Script

```bash
# Run a local file
deno run main.ts

# Run with specific permissions (covered in Module 01)
deno run --allow-net --allow-read main.ts

# Run a remote script directly from URL
deno run https://deno.land/std@0.224.0/examples/welcome.ts

# Watch mode: restart on file changes (like nodemon)
deno run --watch main.ts

# Enable unstable APIs
deno run --unstable-kv main.ts

# Set environment variables
deno run --allow-env MY_VAR=value main.ts
```

### `deno fmt` — Code Formatter

Deno ships with `deno fmt`, a built-in formatter based on `dprint`. It formats TypeScript, JavaScript, JSON, Markdown, and HTML.

```bash
# Format all files in the current directory
deno fmt

# Format specific files
deno fmt main.ts utils/helpers.ts

# Check formatting without modifying files (useful in CI)
deno fmt --check

# Configure in deno.json
# "fmt": { "lineWidth": 100, "indentWidth": 2, "singleQuote": true }
```

### `deno lint` — Linter

```bash
# Lint all files
deno lint

# Lint specific files
deno lint main.ts

# Show all available rules
deno lint --rules

# Apply lint rules in CI (exits non-zero if violations found)
deno lint --quiet
```

### `deno test` — Test Runner

```bash
# Run all test files (files ending in _test.ts, .test.ts, or in __tests__/)
deno test

# Run with specific permissions
deno test --allow-net --allow-read

# Run a specific test file
deno test user_service_test.ts

# Run tests matching a name pattern
deno test --filter "should handle auth"

# Run tests in parallel (default: sequential)
deno test --parallel

# Generate coverage report
deno test --coverage=coverage_dir
deno coverage coverage_dir
```

### `deno check` — Type Check Without Running

```bash
# Type-check a file without executing it
deno check main.ts

# Check all files referenced from an entry point
deno check --all main.ts
```

### `deno compile` — Standalone Binary

```bash
# Compile to a self-contained executable
deno compile --allow-net --allow-read main.ts

# Cross-compile for a different target
deno compile --target x86_64-unknown-linux-gnu main.ts

# Set output filename
deno compile --output my-server main.ts

# Available targets:
# x86_64-unknown-linux-gnu    (Linux x86_64)
# aarch64-unknown-linux-gnu   (Linux ARM64)
# x86_64-pc-windows-msvc      (Windows x86_64)
# x86_64-apple-darwin         (macOS Intel)
# aarch64-apple-darwin         (macOS Apple Silicon)
```

### `deno install` — Install a Script as a Global Command

```bash
# Install a Deno script as a CLI command
deno install \
    --allow-net \
    --allow-read \
    --name my-tool \
    ./my-tool.ts

# Install from URL
deno install \
    --allow-net \
    --name serve \
    https://deno.land/std@0.224.0/http/file_server.ts

# The command is now available as: my-tool / serve
```

### `deno repl` — Interactive Shell

```bash
# Start the Deno REPL
deno repl

# REPL with permissions
deno repl --allow-net

# Evaluate code on startup
deno repl --eval 'import { assert } from "jsr:@std/assert"'
```

---

## The `deno.json` Configuration File

`deno.json` is the Deno project configuration file. It is optional but recommended for any project larger than a single file.

```json
{
  "name": "@myorg/my-project",
  "version": "1.0.0",

  "tasks": {
    "dev": "deno run --watch --allow-net --allow-read --allow-env src/main.ts",
    "start": "deno run --allow-net --allow-read --allow-env src/main.ts",
    "test": "deno test --allow-net --allow-read tests/",
    "check": "deno check src/main.ts",
    "fmt": "deno fmt",
    "lint": "deno lint"
  },

  "fmt": {
    "lineWidth": 100,
    "indentWidth": 2,
    "singleQuote": false,
    "proseWrap": "preserve"
  },

  "lint": {
    "rules": {
      "tags": ["recommended"],
      "include": ["eqeqeq", "no-eval"],
      "exclude": ["no-explicit-any"]
    }
  },

  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "exactOptionalPropertyTypes": true
  },

  "imports": {
    "@std/assert": "jsr:@std/assert@^1",
    "@std/fs": "jsr:@std/fs@^1",
    "@std/path": "jsr:@std/path@^1",
    "hono": "jsr:@hono/hono@^4"
  }
}
```

Run tasks with `deno task`:
```bash
deno task dev      # Starts dev server with watch mode
deno task test     # Runs all tests
deno task fmt      # Formats all files
```

---

## Import Maps and the JSR Registry

Deno imports modules by URL. To avoid repeating long URLs across files, use an import map in `deno.json`:

### JSR (JavaScript Registry) — The Preferred Source

JSR is the official registry for Deno and modern JavaScript. Packages are TypeScript-native and type-safe.

```typescript
// Without import map
import { assertEquals } from "jsr:@std/assert@^1.0.0";
import { Hono } from "jsr:@hono/hono@^4.0.0";

// With import map in deno.json (cleaner)
import { assertEquals } from "@std/assert";
import { Hono } from "hono";
```

### npm Compatibility

Deno can import npm packages using the `npm:` specifier. No installation step needed.

```typescript
import express from "npm:express@^4";
import { z } from "npm:zod@^3";
import chalk from "npm:chalk@^5";
```

---

## Development Workflow for a New Project

```bash
# 1. Create project directory
mkdir my-deno-project && cd my-deno-project

# 2. Initialize configuration
deno init
# Creates: deno.json, main.ts, main_test.ts

# 3. Edit deno.json to add your tasks and imports
# (see example above)

# 4. Write your code in main.ts
# Deno is ready — no npm install, no setup

# 5. Start development with watch mode
deno task dev

# 6. Run tests
deno task test

# 7. Format and lint before committing
deno fmt && deno lint
```

---

## Key Differences from Node.js

| Feature | Node.js | Deno |
|---|---|---|
| TypeScript | Requires `ts-node` or build step | Native, no configuration |
| Module system | CommonJS (`require`) or ESM | ES Modules only (`import`) |
| Package manager | npm / yarn / pnpm | No package manager; URLs / JSR |
| `package.json` | Required | Optional `deno.json` |
| `node_modules` | Created on disk | Remote modules cached in `DENO_DIR` |
| Security | Full OS access by default | Sandboxed; explicit permission flags |
| Formatter | Prettier (separate install) | Built-in `deno fmt` |
| Linter | ESLint (separate install) | Built-in `deno lint` |
| Test runner | Jest / Vitest (separate install) | Built-in `deno test` |
| Top-level `await` | ES2022+ only | Always supported |

---

## Troubleshooting

**`deno: command not found` after installation**

The `~/.deno/bin` directory is not in your `PATH`. Add this to your shell configuration:
```bash
echo 'export PATH="$HOME/.deno/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**`Error: Relative import path must start with "/", "./" or "../"`**

Deno requires explicit relative imports. Change `import { util } from "utils"` to `import { util } from "./utils.ts"`. Note that the `.ts` extension must be included explicitly in Deno.

**Module cached with old version**

Deno caches downloaded modules in `~/.cache/deno` (Linux/macOS) or `%LOCALAPPDATA%\deno` (Windows). Force re-download:
```bash
deno run --reload main.ts

# Or clear the entire module cache
deno cache --reload jsr:@std/assert@^1
```

**TypeScript errors on a valid import**

Run `deno check main.ts` for detailed type errors. If the import lacks types, some npm packages need `@types/` packages added to `deno.json`:
```json
{
  "imports": {
    "express": "npm:express@^4",
    "@types/express": "npm:@types/express@^4"
  }
}
```
