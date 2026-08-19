# Module 02: Native TypeScript & Web Standards

**Track:** Deno Secure Engine & Edge Runtime
**Category:** TypeScript Runtime & Browser API Compatibility

---

## TypeScript Without Configuration

In Node.js, running TypeScript requires: installing `typescript` and `ts-node` (or `tsx`), creating `tsconfig.json`, configuring module resolution, setting up path aliases, and running a compilation step. In Deno, TypeScript is a first-class language built into the runtime. You run `.ts` files the same way you run `.js` files.

```bash

# Node.js TypeScript setup (required steps)
npm install -D typescript ts-node @types/node
npx tsc --init

# Edit tsconfig.json
npx ts-node src/index.ts

# Deno TypeScript (no setup)
deno run src/main.ts
```

Deno embeds the TypeScript compiler version that ships with each Deno release. The version is displayed in `deno --version`. Type checking happens on demand — `deno run` skips type checking for speed; use `deno check` for explicit type verification.

---

## Type Checking Modes

### Fast Mode: Skip Type Checking

`deno run` does not type-check by default in Deno 2. It transpiles TypeScript to JavaScript (stripping type annotations) and runs it. This is fast but silently ignores type errors.

```bash

# Fast: transpile and run without type checking
deno run main.ts
```

### Explicit Type Check

```bash

# Check types without running
deno check main.ts

# Check all files reachable from the entry point
deno check --all main.ts

# Run AND type-check (slower, use in CI)
deno run --check main.ts
```

### Type Checking in Watch Mode

```bash

# Watch, type-check, and restart on changes
deno run --check --watch main.ts
```

---

## The Deno Global Namespace

The `Deno` global object exposes all runtime APIs. It is available in all Deno programs without any import.

### File System

```typescript
// Reading files
const text = await Deno.readTextFile("./config.json");
const binary = await Deno.readFile("./image.png");        // Uint8Array

// Writing files
await Deno.writeTextFile("./output.txt", "Hello, World!");
await Deno.writeFile("./data.bin", new Uint8Array([0x48, 0x69]));

// File metadata
const stat = await Deno.stat("./config.json");
console.log(stat.size, stat.mtime, stat.isFile);

// Directory operations
await Deno.mkdir("./new-dir", { recursive: true });
for await (const entry of Deno.readDir("./src")) {
  console.log(entry.name, entry.isFile ? "file" : "dir");
}

// Rename and remove
await Deno.rename("./old.txt", "./new.txt");
await Deno.remove("./temp.txt");
await Deno.remove("./temp-dir", { recursive: true });
```

### Environment and Process

```typescript
// Environment variables
const port = Deno.env.get("PORT") ?? "8080";
Deno.env.set("CACHE_TTL", "300");
const allVars = Deno.env.toObject();  // All env vars as a plain object

// Process exit
Deno.exit(0);   // Success
Deno.exit(1);   // Error

// OS information
console.log(Deno.build.os);    // "linux", "darwin", "windows"
console.log(Deno.build.arch);  // "x86_64", "aarch64"
console.log(Deno.version.deno); // "2.1.4"

// Command-line arguments (args after the script name)
console.log(Deno.args);   // ["--port", "8080", "--debug"]

// Process ID
console.log(Deno.pid);   // e.g., 12345
```

### Low-Level I/O

```typescript
// Open a file for reading/writing with fine-grained control
const file = await Deno.open("./data.txt", {
  read: true,
  write: true,
  create: true,
  truncate: false,
});

// Read into a buffer
const buffer = new Uint8Array(1024);
const bytesRead = await file.read(buffer);

// Write from a buffer
const encoder = new TextEncoder();
await file.write(encoder.encode("hello\n"));

// Seek to a position
await file.seek(0, Deno.SeekMode.Start);

// Always close to release the file descriptor
file.close();

// Or use using (requires --unstable or Deno 2.0+)
using fileHandle = await Deno.open("./data.txt", { read: true });
const content = await fileHandle.readable.getReader().read();
// File is automatically closed at end of scope (explicit resource management)
```

---

## Web-Standard APIs: The Same APIs as the Browser

Deno's most distinctive feature beyond security is its commitment to **Web Standards**. APIs that browsers expose are available in Deno without wrapping or custom implementations. This means code that uses these APIs can run in both a browser and Deno without modification.

### `fetch` — HTTP Client

```typescript
// The same fetch() API available in browsers
const response = await fetch("https://api.github.com/users/denoland", {
  headers: {
    "Accept": "application/json",
    "User-Agent": "my-deno-app/1.0",
  },
});

if (!response.ok) {
  throw new Error(`GitHub API error: ${response.status}`);
}

const user = await response.json() as { login: string; public_repos: number };
console.log(`${user.login} has ${user.public_repos} public repos`);

// Streaming response body
const stream = await fetch("https://example.com/large-file.bin");
for await (const chunk of stream.body!) {
  // Process each chunk as Uint8Array
  process(chunk);
}
```

### `URL` and `URLSearchParams`

```typescript
const url = new URL("https://api.example.com/search?q=deno&page=2");
console.log(url.hostname);        // "api.example.com"
console.log(url.pathname);        // "/search"
console.log(url.searchParams.get("q"));    // "deno"
console.log(url.searchParams.get("page")); // "2"

// Build URLs safely
const apiUrl = new URL("/users/123", "https://api.example.com");
apiUrl.searchParams.set("format", "json");
console.log(apiUrl.toString());
// "https://api.example.com/users/123?format=json"
```

### `Request` and `Response`

```typescript
// Construct Request objects exactly as in browser Service Workers
const req = new Request("https://api.example.com/data", {
  method: "POST",
  headers: new Headers({
    "Content-Type": "application/json",
    "Authorization": `Bearer ${token}`,
  }),
  body: JSON.stringify({ key: "value" }),
});

// Construct Response objects
const response = new Response(
  JSON.stringify({ success: true }),
  {
    status: 201,
    headers: { "Content-Type": "application/json" },
  }
);
```

### `crypto` — Web Crypto API

```typescript
// Generate a random UUID (available natively without any import)
const id = crypto.randomUUID();   // "550e8400-e29b-41d4-a716-446655440000"

// Cryptographic operations via SubtleCrypto
const key = await crypto.subtle.generateKey(
  { name: "HMAC", hash: "SHA-256" },
  true,   // extractable
  ["sign", "verify"]
);

const data = new TextEncoder().encode("message to sign");
const signature = await crypto.subtle.sign("HMAC", key, data);

const isValid = await crypto.subtle.verify("HMAC", key, signature, data);
console.log(isValid);  // true

// Generate random bytes
const randomBytes = new Uint8Array(32);
crypto.getRandomValues(randomBytes);
```

### `WebSocket` Client

```typescript
// Same WebSocket API as the browser
const ws = new WebSocket("wss://echo.websocket.org");

ws.addEventListener("open", () => {
  ws.send("Hello, WebSocket!");
});

ws.addEventListener("message", (event) => {
  console.log("Received:", event.data);
  ws.close();
});

ws.addEventListener("close", (event) => {
  console.log(`Closed: ${event.code} ${event.reason}`);
});

ws.addEventListener("error", (event) => {
  console.error("WebSocket error:", event);
});
```

### `TextEncoder` and `TextDecoder`

```typescript
// Encode strings to Uint8Array (UTF-8)
const encoder = new TextEncoder();
const bytes = encoder.encode("Hello, 世界!");

// Decode Uint8Array back to string
const decoder = new TextDecoder("utf-8");
const text = decoder.decode(bytes);
console.log(text);  // "Hello, 世界!"

// Decode other encodings
const latin1Decoder = new TextDecoder("iso-8859-1");
const latin1Text = latin1Decoder.decode(new Uint8Array([72, 101, 108, 108, 111]));
```

### `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`

```typescript
// Identical to browser timers
const timeoutId = setTimeout(() => {
  console.log("Fires after 1 second");
}, 1000);

// Cancel before it fires
clearTimeout(timeoutId);

const intervalId = setInterval(() => {
  console.log("Fires every 500ms");
}, 500);

// Stop the interval
setTimeout(() => clearInterval(intervalId), 3000);

// queueMicrotask — runs before next event loop iteration
queueMicrotask(() => {
  console.log("Runs as a microtask");
});
```

### `EventTarget` and `CustomEvent`

```typescript
class Database extends EventTarget {
  async connect(url: string): Promise<void> {
    // ... connection logic
    this.dispatchEvent(new CustomEvent("connected", {
      detail: { url, timestamp: Date.now() },
    }));
  }
}

const db = new Database();
db.addEventListener("connected", (event: Event) => {
  const e = event as CustomEvent<{ url: string; timestamp: number }>;
  console.log(`Connected to ${e.detail.url} at ${e.detail.timestamp}`);
});
await db.connect("postgres://localhost:5432/mydb");
```

---

## Deno-Specific APIs That Browser Code Can Import Conditionally

Some operations are only meaningful in Deno (reading files, spawning processes). Libraries that target both environments check for Deno:

```typescript
// Check if running in Deno
const isDeno = typeof Deno !== "undefined";

// Check if running in a browser
const isBrowser = typeof window !== "undefined" && typeof document !== "undefined";

// Cross-runtime fetch utility
async function fetchText(url: string): Promise<string> {
  if (isDeno) {
    // Could also use Deno.readTextFile for local URLs
    const res = await fetch(url);
    return res.text();
  } else {
    const res = await window.fetch(url);
    return res.text();
  }
}
```

---

## TypeScript Configuration in Deno

Deno uses the `compilerOptions` field in `deno.json` to configure the embedded TypeScript compiler:

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "noImplicitReturns": true,
    "exactOptionalPropertyTypes": true,
    "noUncheckedIndexedAccess": true,
    "lib": ["dom", "dom.iterable", "esnext", "deno.ns"]
  }
}
```

The `"lib"` field controls which global type declarations are available. `"deno.ns"` includes the `Deno` namespace types. `"dom"` includes browser API types like `fetch`, `URL`, `Request`, `Response`, `WebSocket`, and `crypto` — these are included by default because Deno implements them.

---

## Troubleshooting

### `Cannot find name 'Deno'`

Your IDE's TypeScript server does not have Deno types loaded. Install the Deno VSCode extension and enable Deno for the workspace (`Deno: Initialize Workspace Configuration`). This adds `"deno.enable": true` to `.vscode/settings.json` and the Deno language server provides types.

### `Type 'string' is not assignable to type 'never'`

You have `exactOptionalPropertyTypes: true` in your compiler options (a very strict option). Optional properties typed as `string | undefined` require explicit `undefined` handling at call sites. Either relax this option or update the code to handle `undefined` explicitly.

### `fetch is not defined` when running in an old Deno version

`fetch` is built into Deno since version 1.9.0. If you see this error, upgrade Deno: `deno upgrade`.
