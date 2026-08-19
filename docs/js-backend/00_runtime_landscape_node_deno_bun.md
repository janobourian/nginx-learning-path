# Module 00: Server-Side JavaScript Runtimes — Node.js, Deno & Bun

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Server Runtime Foundations, Engine Architecture & Toolchain Comparison

---

## 1. The Multi-Runtime JavaScript Landscape

Server-side JavaScript is no longer a Node.js monopoly. Today, enterprise architectures choose between three premier runtimes:

```text
┌─────────────────────────────────────────────────────────────┐
│                 The 3 Server JavaScript Runtimes            │
├───────────────────┬──────────────────┬──────────────────────┤
│ Metric / Feature  │ Node.js (v20+)   │ Deno (v2.0+)         │ Bun (v1.1+)          │
├───────────────────┼──────────────────┼──────────────────────┤
│ **JS Engine**     │ Google V8        │ Google V8            │ Apple JavaScriptCore │
│ **Underlying Core**│ C++ / libuv     │ Rust / Tokio         │ Zig                  │
│ **Security Sandbox**│ Opt-in Flags   │ **Default Secure**   │ Native OS permissions│
│ **Native TS**     │ Experimental     │ **Built-in First-Cl**│ **Built-in First-Cl**│
│ **Package Engine**│ npm, pnpm, yarn  │ JSR + npm            │ Ultra-fast native npm│
│ **Web Standards** │ Partial          │ **100% Web Standards**│ High                │
└───────────────────┴──────────────────┴──────────────────────┘
```

---

## 2. Architectural Comparison: V8 vs JavaScriptCore

### 1. Google V8 (Node.js & Deno)

- **Ignition Bytecode Interpreter** + **TurboFan Optimizing JIT Compiler**.
- Aggressive JIT inlining and Hidden Class optimizations.
- Generational GC (Orinoco) optimized for long-lived backend heaps.

### 2. Apple JavaScriptCore / JSC (Bun)

- Multi-tier execution: **LLInt (Low-Level Interpreter) ──► Baseline JIT ──► DFG (Data Flow Graph) JIT ──► FTL (Faster Than Light) JIT**.
- Faster cold-start initialization and lower baseline memory usage than V8.

---

## 3. The Unified Web Standards Standard

All modern runtimes converge on standard **W3C / WHATWG Web APIs**, allowing the exact same code to run seamlessly across Node.js, Deno, Bun, and Cloudflare Workers:

```javascript
// Cross-Runtime Standard HTTP Server (Runs identically in Deno, Bun, and Node 20!):
export default {
  port: 3000,
  fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return Response.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
      });
    }

    return new Response('Enterprise Multi-Runtime Endpoint', {
      status: 200,
      headers: { 'content-type': 'text/plain' },
    });
  },
};
```

---

## 4. When to Choose Which Runtime

```text
┌─────────────────────────────────────────────────────────────┐
│                 Runtime Selection Decision Guide            │
├─────────────────────────────────────────────────────────────┤
│ **Choose Node.js when:**                                    │
│ - Building within mature enterprise ecosystems with legacy  │
│   native C++ N-API addons (e.g. Oracle, SAP connectors).    │
│ - Requiring strict LTS 30-month corporate support lifecycles│
├─────────────────────────────────────────────────────────────┤
│ **Choose Deno when:**                                       │
│ - Prioritizing zero-trust security sandboxing (Edge & SaaS).│
│ - Building modern TypeScript-first monorepos with JSR.      │
├─────────────────────────────────────────────────────────────┤
│ **Choose Bun when:**                                        │
│ - Maximum raw I/O throughput and ultra-fast CLI tooling     │
│   (package installation, testing, bundling) are critical.   │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Writing Runtime-Agnostic Enterprise Code

To write libraries and microservices that execute across Node, Deno, and Bun without modification:

```javascript
// src/utils/runtime_detector.js
export function detectRuntime() {
  if (typeof Deno !== 'undefined') {
    return { name: 'deno', version: Deno.version.deno };
  }
  if (typeof Bun !== 'undefined') {
    return { name: 'bun', version: Bun.version };
  }
  if (typeof process !== 'undefined' && process.versions?.node) {
    return { name: 'node', version: process.versions.node };
  }
  return { name: 'unknown', version: '0.0.0' };
}

console.log('Active Server Runtime:', detectRuntime());
```

---

## Troubleshooting & Best Practices

1. **Avoid Runtime-Specific Globals in Shared Code**
   Never reference `Deno.readTextFile` or `Bun.file` directly in shared business logic. Use standard `fetch()`, `crypto.subtle`, or abstract file system calls behind an adapter repository pattern.

2. **Standardize on ESM (`import` / `export`)**
   CommonJS (`require`) is not supported natively in modern web standards or browser edge runtimes. Always configure `"type": "module"` in `package.json`.
