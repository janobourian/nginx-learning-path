# Module 03: Deno Standard Library & JSR Registry

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Modules, Imports & Package Ecosystem

---

## Why Deno Has No Package Manager

Node.js's `npm` is both a package manager and a registry. It installs packages into `node_modules`, a local directory that can contain hundreds of megabytes of transitive dependencies. The `package-lock.json` pins exact versions. Running `npm install` on a new machine re-downloads everything.

Deno takes a different approach: **modules are imported by URL**. There is no install step. The first time Deno encounters an import URL, it downloads and caches the module globally. On subsequent runs it uses the cache. The module URL itself encodes the version:

```typescript
// The version is in the URL — explicit and auditable
import { assertEquals } from "jsr:@std/assert@^1.0.0";
import { Hono } from "jsr:@hono/hono@^4.5.0";
import express from "npm:express@4.18.2";
```

There is no separate lock file step. `deno.lock` is automatically maintained by Deno and should be committed to version control.

---

## The Three Module Sources

### 1. JSR (JavaScript Registry) — `jsr:` specifier

JSR (jsr.io) is the modern registry for TypeScript-native packages. It is the successor to `deno.land/x`. Packages on JSR:
- Are authored in TypeScript and distributed with type declarations
- Cannot contain lifecycle scripts (`postinstall`, etc.) that could run arbitrary code
- Have provenance verification (package content linked to a git commit)
- Support Deno, Node.js, Bun, and browsers

```typescript
import { assertEquals, assertThrows } from "jsr:@std/assert@^1";
import { walk, exists } from "jsr:@std/fs@^1";
import { join, basename, extname } from "jsr:@std/path@^1";
import { parse } from "jsr:@std/csv@^1";
import { Hono } from "jsr:@hono/hono@^4";
```

### 2. npm — `npm:` specifier

Deno 1.28+ can import npm packages directly. Deno maintains its own npm package cache (not `node_modules`) and polyfills Node.js built-in modules.

```typescript
import express from "npm:express@^4";
import { z } from "npm:zod@^3";
import lodash from "npm:lodash@^4";
import { Redis } from "npm:ioredis@^5";
```

### 3. HTTP/HTTPS URLs — Legacy Style

Importing from HTTPS URLs directly still works and is how `deno.land/x` packages are distributed:

```typescript
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
```

This pattern is being superseded by JSR but remains valid.

---

## The Import Map: Cleaning Up Import Paths

Instead of repeating version specifiers across every file, define an import map in `deno.json`:

```json
{
  "imports": {
    "@std/assert": "jsr:@std/assert@^1",
    "@std/fs": "jsr:@std/fs@^1",
    "@std/path": "jsr:@std/path@^1",
    "@std/testing": "jsr:@std/testing@^1",
    "@std/streams": "jsr:@std/streams@^1",
    "hono": "jsr:@hono/hono@^4",
    "zod": "npm:zod@^3",
    "ioredis": "npm:ioredis@^5"
  }
}
```

Now all files use short, clean imports:

```typescript
// Before import map (repeating versions everywhere):
import { assertEquals } from "jsr:@std/assert@^1.0.0";

// After import map (version managed centrally in deno.json):
import { assertEquals } from "@std/assert";
```

---

## The Deno Standard Library

The Deno Standard Library (`@std`) is maintained by the Deno team and covers the most common utility needs. Every package follows semver and has comprehensive tests.

### `@std/assert` — Testing Assertions

```typescript
import {
  assert,
  assertEquals,
  assertNotEquals,
  assertStrictEquals,
  assertThrows,
  assertRejects,
  assertExists,
  assertArrayIncludes,
  assertStringIncludes,
  assertMatch,
  assertObjectMatch,
} from "@std/assert";

// Basic assertions
assert(1 + 1 === 2);
assertEquals([1, 2, 3], [1, 2, 3]);
assertNotEquals("hello", "world");

// Throws assertion
assertThrows(
  () => { throw new TypeError("bad input"); },
  TypeError,
  "bad input",
);

// Async throws
await assertRejects(
  async () => { await Promise.reject(new Error("async error")); },
  Error,
  "async error",
);

// Object subset matching (ignores extra properties)
assertObjectMatch(
  { name: "Alice", role: "admin", createdAt: new Date() },
  { name: "Alice", role: "admin" },   // Only checks these two fields
);
```

### `@std/path` — Cross-Platform Path Operations

```typescript
import { join, dirname, basename, extname, resolve, relative, isAbsolute } from "@std/path";

join("/usr", "local", "bin", "deno");   // "/usr/local/bin/deno"
dirname("/home/user/config.json");       // "/home/user"
basename("/home/user/config.json");      // "config.json"
basename("/home/user/config.json", ".json"); // "config"
extname("module.ts");                   // ".ts"
resolve("../config.json");              // Absolute path
relative("/app", "/app/src/main.ts");   // "src/main.ts"
isAbsolute("/usr/bin");                 // true
```

### `@std/fs` — File System Utilities

```typescript
import {
  exists,
  ensureDir,
  ensureFile,
  copy,
  move,
  emptyDir,
  walk,
  expandGlob,
} from "@std/fs";

// Check if path exists
const fileExists = await exists("./config.json");
const dirExists = await exists("./logs", { isDirectory: true });

// Create directory tree (like mkdir -p)
await ensureDir("./data/cache/images");

// Create file and its parent directories if they don't exist
await ensureFile("./logs/app.log");

// Copy file or directory
await copy("./src", "./dist", { overwrite: true });

// Move/rename
await move("./temp.txt", "./archive/temp.txt");

// Walk directory tree recursively
for await (const entry of walk("./src", {
  exts: [".ts"],              // Only TypeScript files
  skip: [/node_modules/],     // Skip these paths
})) {
  console.log(entry.path);
}

// Glob expansion
for await (const file of expandGlob("**/*.ts", { root: "./src" })) {
  console.log(file.path);
}
```

### `@std/streams` — Stream Utilities

```typescript
import {
  toText,
  toArrayBuffer,
  toBlob,
  toJson,
  mergeReadableStreams,
  TextLineStream,
} from "@std/streams";

// Convert a ReadableStream to a string
const response = await fetch("https://api.example.com/data");
const text = await toText(response.body!);

// Read lines from a file as a stream
const file = await Deno.open("./large-log.txt");
const lineStream = file.readable
  .pipeThrough(new TextDecoderStream())
  .pipeThrough(new TextLineStream());

for await (const line of lineStream) {
  console.log(line);
}
```

### `@std/encoding` — Data Encoding

```typescript
import { encodeBase64, decodeBase64 } from "@std/encoding/base64";
import { encodeHex, decodeHex } from "@std/encoding/hex";

const encoded = encodeBase64("Hello, World!");       // "SGVsbG8sIFdvcmxkIQ=="
const decoded = new TextDecoder().decode(decodeBase64("SGVsbG8sIFdvcmxkIQ=="));

const hex = encodeHex(new TextEncoder().encode("Hello"));  // "48656c6c6f"
const bytes = decodeHex("48656c6c6f");
```

### `@std/datetime` — Date Formatting

```typescript
import { format, parse, difference, isLeap } from "@std/datetime";

format(new Date(), "yyyy-MM-dd HH:mm:ss");     // "2026-08-18 15:30:00"
format(new Date(), "dd/MM/yyyy");               // "18/08/2026"

const parsed = parse("2026-08-18", "yyyy-MM-dd");

const diff = difference(new Date("2026-01-01"), new Date("2026-08-18"));
console.log(diff.days);     // 229

isLeap(2024);  // true
```

### `@std/testing/bdd` — BDD-Style Tests

```typescript
import { describe, it, beforeAll, afterAll, beforeEach, afterEach } from "@std/testing/bdd";
import { assertEquals } from "@std/assert";

describe("UserService", () => {
  let db: Database;

  beforeAll(async () => {
    db = await Database.connect(":memory:");
  });

  afterAll(async () => {
    await db.close();
  });

  describe("createUser", () => {
    it("creates a user with hashed password", async () => {
      const user = await UserService.create(db, {
        name: "Alice",
        email: "alice@example.com",
        password: "secure123",
      });

      assertEquals(user.name, "Alice");
      assert(user.passwordHash !== "secure123");
    });

    it("rejects duplicate email", async () => {
      await assertRejects(
        () => UserService.create(db, { email: "alice@example.com", ... }),
        Error,
        "Email already registered",
      );
    });
  });
});
```

---

## Managing the Module Cache

```bash
# Show the Deno cache directory
deno info

# Show all cached modules and their dependencies
deno info --json | jq '.moduleDependencies'

# Force re-download of a specific module
deno cache --reload jsr:@std/assert@^1

# Force re-download of all modules in the project
deno cache --reload deno.json

# Cache modules for offline use (pre-warm the cache in Docker build)
deno cache src/main.ts
```

The module cache is located at:
- Linux/macOS: `~/.cache/deno/`
- Windows: `%LOCALAPPDATA%\deno\`

---

## Lock File (`deno.lock`)

Deno automatically creates and updates `deno.lock` when you run `deno run`, `deno cache`, or `deno test`. This file pins the exact content hash of every dependency:

```json
{
  "version": "4",
  "specifiers": {
    "jsr:@std/assert@^1": "jsr:@std/assert@1.0.9",
    "jsr:@hono/hono@^4": "jsr:@hono/hono@4.5.3"
  },
  "jsr": {
    "@std/assert@1.0.9": {
      "integrity": "a3e2e..."
    }
  }
}
```

Commit `deno.lock` to version control. When other developers or CI runs your project, Deno verifies the integrity of downloaded modules against the lock file, preventing supply chain attacks.

---

## Publishing to JSR

```typescript
// my-module/mod.ts — the main export file
/**
 * A utility library for working with ISO 8601 durations.
 * @module
 */

export { parseDuration } from "./parse.ts";
export { formatDuration } from "./format.ts";
export type { Duration } from "./types.ts";
```

```json
// jsr.json (or in deno.json)
{
  "name": "@myorg/duration",
  "version": "1.0.0",
  "exports": "./mod.ts",
  "publish": {
    "include": ["mod.ts", "*.ts", "README.md", "LICENSE"],
    "exclude": ["**/*_test.ts", "examples/"]
  }
}
```

```bash
# Publish to JSR (requires authentication)
deno publish

# Dry run to check what would be published
deno publish --dry-run
```

---

## Troubleshooting

**`Module not found "jsr:@std/assert@^1"`**

Ensure you have internet access during the first run. If behind a corporate proxy, set `HTTPS_PROXY` and `HTTP_PROXY` environment variables. Deno respects these when fetching modules.

**`Lock file is out of date`**

The lock file references a version that no longer exists or has changed integrity. Run `deno cache --reload deno.json` to regenerate the lock file.

**npm package has no type definitions**

For npm packages without bundled types, add the `@types/` package to `deno.json`:
```json
{
  "imports": {
    "pg": "npm:pg@^8",
    "@types/pg": "npm:@types/pg@^8"
  }
}
```
