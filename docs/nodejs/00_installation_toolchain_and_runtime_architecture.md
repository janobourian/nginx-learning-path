# Module 00: Node.js Architecture, Multi-Runtime Toolchains & Foundations

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Runtime Foundations, Toolchains & Architecture

---

## 1. What Is Node.js?

**Node.js** is an open-source, cross-platform JavaScript runtime environment built on Google's high-performance **V8 JavaScript Engine** and the **libuv** asynchronous I/O platform abstraction library.

Before Node.js was created by Ryan Dahl in 2009, JavaScript was confined to web browsers. Node.js brought JavaScript to servers, command-line tooling, and desktop systems by combining:

1. **Google V8 Engine**: Compiles JavaScript source code directly into native machine code (x86_64 / ARM64).
2. **libuv**: A high-performance C library that implements the asynchronous **Event Loop**, thread pool, and non-blocking I/O across epoll (Linux), kqueue (macOS/BSD), and IOCP (Windows).
3. **Core C++ Bindings & Node.js Native API (N-API)**: Bridges JavaScript userland code to OS-level system calls (networking, file system, cryptography, child processes).

```text
Node.js Runtime Architecture Stack:
┌─────────────────────────────────────────────────────────────┐
│          1. Application Code (JavaScript / TypeScript)      │
├─────────────────────────────────────────────────────────────┤
│          2. Node.js Standard Library (`node:fs`, `node:http`)│
├─────────────────────────────────────────────────────────────┤
│          3. Node.js C++ Core Bindings & N-API Bridges       │
├──────────────────────────────┬──────────────────────────────┤
│ 4. Google V8 Engine          │ 5. libuv (C Library)         │
│    - JIT Compilation (Ignition & TurboFan) - Event Loop     │
│    - Garbage Collector (Orinoco)           - 4-Thread Pool  │
│    - Call Stack & Heap Memory Allocation   - Non-Blocking IO│
├──────────────────────────────┴──────────────────────────────┤
│ 6. Core C/C++ Libraries: OpenSSL (Crypto), zlib, llhttp, c-ares │
├─────────────────────────────────────────────────────────────┤
│ 7. Operating System Kernel: Linux (epoll), macOS (kqueue), Windows (IOCP) │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Managing Node.js Versions (NVM, FNM & Volta)

In enterprise engineering, developers switch between multiple Active LTS (Long-Term Support) versions across microservices. **Fast Node Manager (`fnm`)** is modern, written in Rust, and 20x faster than legacy shell-based managers:

```bash

# Install fnm (macOS / Linux)
curl -fsSL https://fnm.vercel.app/install | bash

# Install and switch to latest LTS
fnm install --lts
fnm use lts-latest

# Pin project Node version via .nvmrc or .node-version
node -v > .node-version
```

---

## 3. Package Managers: `npm`, `pnpm`, and `yarn`

| Package Manager | Storage Mechanism | Disk Space Efficiency | Install Speed |
| :--- | :--- | :--- | :--- |
| **`npm`** | Flat `node_modules` | Copies duplicate packages for every project | Moderate |
| **`pnpm`** | **Global Content-Addressable Hard-Link Store** | **Sub-second linking; saves 80% disk space** | **Ultra-Fast** |
| **`yarn` (Berry/PnP)** | Plug'n'Play Zip Cache | In-memory dependency virtual file system | Fast |

```bash

# Enable corepack (built into Node.js) to manage pnpm & yarn automatically
corepack enable
corepack prepare pnpm@latest --activate
```

---

## 4. Native ESM vs CommonJS

Node.js supports two distinct module systems:

```text
┌─────────────────────────────────────────────────────────────┐
│               CommonJS (CJS) vs ECMAScript Modules (ESM)    │
├────────────────────┬──────────────────┬─────────────────────┤
│ Feature            │ CommonJS (`.cjs`)│ Modern ESM (`.mjs`) │
├────────────────────┼──────────────────┼─────────────────────┤
│ **Syntax**         │ `require()`,     │ `import`, `export`  │
│                    │ `module.exports` │                     │
├────────────────────┼──────────────────┼─────────────────────┤
│ **Loading Model**  │ **Synchronous**  │ **Asynchronous**    │
├────────────────────┼──────────────────┼─────────────────────┤
│ **Top-Level Await**│ No               │ **Yes** (`await ...`│
│                    │                  │ outside functions)  │
├────────────────────┼──────────────────┼─────────────────────┤
│ **Tree Shaking**   │ Difficult/Dynamic│ **Static Analysis** │
└────────────────────┴──────────────────┴─────────────────────┘
```

### Enabling ESM in `package.json`

```json
{
  "name": "enterprise-node-app",
  "version": "1.0.0",
  "type": "module", // ◄── Enforces native ESM throughout the project!
  "scripts": {
    "start": "node src/main.js",
    "dev": "node --watch src/main.js" // Native Node.js file watcher!
  }
}
```

---

## 5. Built-in Modern Node.js Tooling (No External Dependencies Needed!)

Node.js 20+ includes native replacements for legacy external tools:

```bash

# 1. Native File Watcher (Replaces nodemon)
node --watch src/server.js

# 2. Native Environment Variable Loader (Replaces dotenv)
node --env-file=.env src/server.js

# 3. Native Test Runner (Replaces Jest/Mocha for unit tests)
node --test test/**/*.test.js

# 4. Native TypeScript Execution (Node.js 22.6+ type stripping)
node --experimental-strip-types src/index.ts
```

---

## 6. Complete Production Microservice Entry Point (`src/main.js`)

```javascript
// src/main.js
import http from 'node:http';
import os from 'node:os';
import process from 'node:process';

const PORT = Number(process.env.PORT) || 3000;

// Create non-blocking HTTP server:
const server = http.createServer((req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    const payload = JSON.stringify({
      status: 'healthy',
      nodeVersion: process.version,
      uptimeSec: Math.floor(process.uptime()),
      memoryUsageMb: Math.round(process.memoryUsage().rss / 1024 / 1024),
      hostname: os.hostname(),
    });

    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
    });
    res.end(payload);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`[Node.js Runtime]: Server listening on http://localhost:${PORT}`);
  console.log(`[Process Info]: PID=${process.pid}, Arch=${process.arch}, Platform=${process.platform}`);
});

// Graceful Shutdown on OS termination signals:
function handleShutdown(signal) {
  console.log(`\nReceived ${signal}. Closing HTTP connections gracefully...`);
  server.close(() => {
    console.log('HTTP server closed. Exiting process.');
    process.exit(0);
  });

  // Force exit if connections take longer than 10 seconds to drain:
  setTimeout(() => {
    console.error('Forced shutdown timeout reached. Terminating.');
    process.exit(1);
  }, 10000).unref();
}

process.on('SIGTERM', () => handleShutdown('SIGTERM'));
process.on('SIGINT', () => handleShutdown('SIGINT'));
```

---

## Troubleshooting & Best Practices

1. **Always Use the `node:` Prefix for Core Modules**
   Write `import fs from 'node:fs'` instead of `import fs from 'fs'`. The `node:` prefix guarantees that Node resolves the official built-in module, completely preventing dependency-confusion security attacks from malicious npm packages of the same name.

2. **Unref Shutdown Timers**
   When creating timeout safety nets during shutdown, call `.unref()` on the `setTimeout` handle. This prevents the timer from holding the Node.js event loop open if all connections finish closing sooner.
