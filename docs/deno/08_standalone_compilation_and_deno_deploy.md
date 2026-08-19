# Module 08: Standalone Compilation & Deno Deploy

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Distribution & Edge Deployment

---

## Standalone Executables with `deno compile`

`deno compile` bundles your TypeScript application together with the entire Deno runtime into a single self-contained binary. The resulting executable runs on any target machine without requiring Deno to be installed — it contains everything it needs.

This solves a common deployment problem: how do you distribute a TypeScript CLI tool or server to machines that don't have Node.js, Deno, or any JavaScript runtime installed? With `deno compile`, you ship one file.

---

## Basic Compilation

```bash

# Compile the current platform's native binary
deno compile \
  --allow-net \
  --allow-read=./config.json \
  --allow-env=PORT,DATABASE_URL \
  --output dist/api-server \
  src/main.ts

# The output is a self-contained binary
ls -la dist/api-server   # ~100MB — includes the Deno runtime
./dist/api-server        # Runs directly, no Deno needed on the target machine
```

The permissions you specify in `deno compile` are **baked into the binary**. Users running the compiled executable cannot grant or deny permissions — whatever you compiled in is what the binary uses. This is a security feature: the binary only has the capabilities it was built with.

---

## Cross-Compilation for Different Platforms

```bash

# Compile for Linux x86_64 (from macOS or any platform)
deno compile \
  --target x86_64-unknown-linux-gnu \
  --allow-net \
  --allow-env \
  --output dist/server-linux-x64 \
  src/main.ts

# Compile for macOS Apple Silicon
deno compile \
  --target aarch64-apple-darwin \
  --allow-net \
  --allow-env \
  --output dist/server-macos-arm \
  src/main.ts

# Compile for Windows x64
deno compile \
  --target x86_64-pc-windows-msvc \
  --allow-net \
  --allow-env \
  --output dist/server-win-x64.exe \
  src/main.ts

# Compile for Linux ARM64 (Raspberry Pi, AWS Graviton)
deno compile \
  --target aarch64-unknown-linux-gnu \
  --allow-net \
  --allow-env \
  --output dist/server-linux-arm64 \
  src/main.ts
```

Available targets:

- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu`
- `x86_64-pc-windows-msvc`
- `x86_64-apple-darwin`
- `aarch64-apple-darwin`

---

## CLI Tool Example: Compiled Binary

```typescript
// src/cli.ts — a CLI tool that analyzes JavaScript file sizes
import { parse } from "@std/flags";
import { walk } from "@std/fs";
import { join } from "@std/path";

const flags = parse(Deno.args, {
  string: ["dir", "ext"],
  boolean: ["help", "verbose"],
  default: { dir: ".", ext: ".js" },
  alias: { h: "help", v: "verbose", d: "dir" },
});

if (flags.help) {
  console.log(`
js-analyzer — Analyze JavaScript file sizes

USAGE:
  js-analyzer [OPTIONS]

OPTIONS:
  -d, --dir <path>    Directory to scan (default: .)
  --ext <ext>         File extension to match (default: .js)
  -v, --verbose       Show each file's size
  -h, --help          Show this help
`);
  Deno.exit(0);
}

interface FileInfo {
  path: string;
  size: number;
}

const files: FileInfo[] = [];

for await (const entry of walk(flags.dir, { exts: [flags.ext], includeDirs: false })) {
  const stat = await Deno.stat(entry.path);
  files.push({ path: entry.path, size: stat.size });
}

files.sort((a, b) => b.size - a.size);

const totalBytes = files.reduce((sum, f) => sum + f.size, 0);
const totalKB = (totalBytes / 1024).toFixed(2);

console.log(`\n📦 Found ${files.length} ${flags.ext} files (${totalKB} KB total)\n`);

if (flags.verbose) {
  for (const f of files) {
    const kb = (f.size / 1024).toFixed(2);
    console.log(`  ${kb.padStart(8)} KB  ${f.path}`);
  }
  console.log();
}

// Top 5 largest
console.log("Top 5 largest files:");
for (const f of files.slice(0, 5)) {
  const kb = (f.size / 1024).toFixed(2);
  console.log(`  ${kb.padStart(8)} KB  ${f.path}`);
}
```

```bash

# Compile it into a CLI tool
deno compile \
  --allow-read \
  --output js-analyzer \
  src/cli.ts

# Use it anywhere without Deno installed
./js-analyzer --dir ./node_modules --ext .js
./js-analyzer --dir ./src --ext .ts --verbose
```

---

## Bundling with `deno bundle` (Legacy) and ESBuild

`deno bundle` (deprecated in Deno 2) produced a single JavaScript file. The modern approach for creating browser-compatible bundles is using ESBuild via npm:

```typescript
// build.ts — bundle with ESBuild
import * as esbuild from "npm:esbuild@^0.23";
import { denoPlugins } from "jsr:@luca/esbuild-deno-loader@^0.11";

const result = await esbuild.build({
  plugins: [...denoPlugins()],
  entryPoints: ["./src/main.ts"],
  outfile: "./dist/bundle.js",
  bundle: true,
  minify: true,
  platform: "browser",
  target: ["es2022"],
  sourcemap: "external",
  format: "esm",
});

console.log("Bundle complete:", result.outputFiles?.length ?? "written to disk");
await esbuild.stop();
```

```bash
deno run --allow-read --allow-write --allow-env build.ts
```

---

## Deno Deploy

Deno Deploy is a serverless edge computing platform that runs Deno programs globally on V8 isolates. Your code runs in 35+ regions simultaneously, with requests routed to the nearest region.

Key characteristics:

- **Isolate-based**: No containers, no cold start. V8 isolates start in milliseconds.
- **Edge-native**: Code runs 20-50ms from most users globally.
- **KV included**: Deno KV on Deploy uses FoundationDB for globally consistent storage.
- **Queues and Cron included**: The same `kv.enqueue()` and `Deno.cron()` APIs work globally.
- **No persistent file system**: File reads only work on assets bundled at deploy time.

### Deploying to Deno Deploy

```bash

# Install the deployctl CLI
deno install --allow-read --allow-write --allow-env --allow-net --allow-run \
  --name deployctl \
  jsr:@deno/deployctl

# Deploy from the command line
deployctl deploy \
  --project=my-api \
  --entrypoint=src/main.ts

# Deploy with environment variables
deployctl deploy \
  --project=my-api \
  --entrypoint=src/main.ts \
  --env=DATABASE_URL=postgres://... \
  --env=API_SECRET=...
```

### GitHub Actions Deployment

```yaml

# .github/workflows/deploy.yml
name: Deploy to Deno Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # Required for OIDC-based deployment
      contents: read

    steps:

      - uses: actions/checkout@v4

      - name: Deploy to Deno Deploy
        uses: denoland/deployctl@v1
        with:
          project: my-api
          entrypoint: src/main.ts
```

### A Complete Edge API on Deno Deploy

```typescript
// src/main.ts — runs on Deno Deploy's global edge network
import { Hono } from "jsr:@hono/hono@^4";

const kv = await Deno.openKv();
const app = new Hono();

// Middleware: JSON response type
app.use("*", async (c, next) => {
  c.header("Content-Type", "application/json");
  await next();
});

// Middleware: request timing
app.use("*", async (c, next) => {
  const start = Date.now();
  await next();
  c.header("X-Response-Time", `${Date.now() - start}ms`);
  // Expose which edge region served this request
  c.header("X-Deno-Region", Deno.env.get("DENO_REGION") ?? "local");
});

app.get("/api/health", (c) => {
  return c.json({ status: "ok", region: Deno.env.get("DENO_REGION") ?? "local" });
});

app.get("/api/counters/:name", async (c) => {
  const name = c.req.param("name");
  const entry = await kv.get<number>(["counters", name]);
  return c.json({ name, count: entry.value ?? 0 });
});

app.post("/api/counters/:name/increment", async (c) => {
  const name = c.req.param("name");

  // Atomic increment with optimistic concurrency
  let success = false;
  for (let i = 0; i < 10; i++) {
    const entry = await kv.get<number>(["counters", name]);
    const current = entry.value ?? 0;

    const result = await kv.atomic()
      .check(entry)
      .set(["counters", name], current + 1)
      .commit();

    if (result.ok) {
      success = true;
      return c.json({ name, count: current + 1 }, 200);
    }
  }

  return c.json({ error: "Conflict: too many concurrent increments" }, 409);
});

Deno.serve(app.fetch);
```

---

## Troubleshooting

### Compiled binary is very large (~100MB)

The binary includes the entire Deno runtime. This is expected. For container deployments, use the official Deno Docker image instead of compiling — it layers the runtime separately. For CLI distribution, 100MB is acceptable for most tools.

### `deno compile` fails with "permission denied" during cross-compilation

Deno downloads the target platform's binary during cross-compilation. Ensure you have internet access and that your firewall allows connections to `dl.deno.land`.

### On Deno Deploy, `Deno.readTextFile` throws "permission denied"

Deno Deploy runs with `--allow-read` restricted to assets bundled at deploy time. You cannot read arbitrary filesystem paths. Use Deno KV for persistent data and bundle static assets in the deployment.

### KV data differs between edge regions on Deno Deploy

Deno KV on Deploy uses strong consistency by default — reads see the latest committed value from any region. If you see stale data, ensure you are awaiting the `kv.get()` call and not using any local caching layer that bypasses KV.
