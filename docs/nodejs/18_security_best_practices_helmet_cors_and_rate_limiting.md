# Module 18: Security Engineering — OWASP Top 10, Prototype Pollution & Node.js Permissions

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Application Security, OWASP Defense & Runtime Permissions

---

## 1. The OWASP Top 10 in Node.js

Enterprise Node.js applications are prime targets for automated web attacks. Securing Node.js requires defense-in-depth across multiple architectural layers:

```
┌─────────────────────────────────────────────────────────────┐
│                 Node.js Security Defense Stack              │
├────────────────────┬────────────────────────────────────────┤
│ **1. Runtime**     │ Node.js Native Permission Model        │
│    **Layer**       │ (`--allow-fs-read`, `--allow-net`).    │
├────────────────────┼────────────────────────────────────────┤
│ **2. HTTP Layer**  │ Helmet (CSP, HSTS), CORS, Rate Limiting│
├────────────────────┼────────────────────────────────────────┤
│ **3. Logic Layer** │ Prototype Pollution defense, Zod DTOs  │
├────────────────────┼────────────────────────────────────────┤
│ **4. Data Layer**  │ Parameterized SQL queries, NoSQL sanit.│
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Hardening HTTP Headers with Helmet

**`helmet`** sets critical security response headers that protect browsers against XSS, clickjacking, and MIME-sniffing:

```javascript
// src/security/helmet_config.js
import helmet from 'helmet';

export const hardenedHelmet = helmet({
  // 1. Content Security Policy (Strict script whitelisting):
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'trusted-cdn.com'"],
      styleSrc: ["'self'", "'fonts.googleapis.com'"],
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'", 'https://api.enterprise.acme.com'],
      objectSrc: ["'none'"],
      upgradeInsecureRequests: [],
    },
  },
  // 2. HTTP Strict Transport Security (Forces HTTPS for 1 year + subdomains):
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
  // 3. Prevent Clickjacking (X-Frame-Options: DENY):
  frameguard: { action: 'deny' },
  // 4. Prevent MIME-Type Sniffing:
  noSniff: true,
  // 5. Hide X-Powered-By: Express:
  hidePoweredBy: true,
});
```

---

## 3. Prototype Pollution Vulnerabilities & Prevention

In JavaScript, objects inherit properties from `Object.prototype`. 

If an application performs an unvalidated recursive merge on user-provided JSON (`req.body`), an attacker can inject properties into `__proto__`, **polluting all JavaScript objects across the entire application runtime**:

```javascript
// ❌ VULNERABLE CODE (Recursive Merge without Proto Filtering):
function vulnerableMerge(target, source) {
  for (const key in source) {
    if (typeof source[key] === 'object' && source[key] !== null) {
      if (!target[key]) target[key] = {};
      vulnerableMerge(target[key], source[key]); // Attacker passes {"__proto__": {"isAdmin": true}}
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
```

### Prototype Pollution Defense Strategies:

1. **Use `Map` Instead of Plain Objects**: `Map` instances do not have prototype chain lookup keys.
2. **Create Objects with `Object.create(null)`**: Objects created without prototype are completely immune to prototype pollution.
3. **Block Proto Keys in Merges**:

```javascript
// ✅ SECURE MERGE:
const FORBIDDEN_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

export function secureMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (FORBIDDEN_KEYS.has(key)) continue; // Drop malicious prototype keys!

    if (typeof source[key] === 'object' && source[key] !== null && !Array.isArray(source[key])) {
      if (!target[key]) target[key] = Object.create(null);
      secureMerge(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
```

---

## 4. Preventing Command Injection (`exec` vs `execFile`)

Never execute shell commands using `child_process.exec()` with concatenated user input:

```javascript
import { exec, execFile } from 'node:child_process';

// ❌ CRITICAL VULNERABILITY: Shell command injection!
// If fileName = "test.png; rm -rf /", the shell executes the rm command!
exec(`convert ${req.query.fileName} output.png`);

// ✅ SECURE: execFile bypasses the shell completely and passes arguments as raw array:
execFile('convert', [req.query.fileName, 'output.png'], (err, stdout) => {
  // Safe from shell metacharacter injection!
});
```

---

## 5. The Node.js Native Permission Model (Node.js 20+)

Node.js features an experimental **Native Permission Model** built into the C++ runtime, allowing you to restrict system capabilities without third-party sandboxes:

```bash
# Start Node with restricted permissions:
node --experimental-permission \
  --allow-fs-read=/app/public,/app/certs \
  --allow-fs-write=/app/logs \
  --allow-net=api.stripe.com,database.internal \
  src/server.js
```

If any dependency or compromised package attempts to read `/etc/passwd` or spawn a child process, the Node.js runtime **immediately aborts the operation with an `ERR_ACCESS_DENIED` security error**.

```javascript
// Querying permissions programmatically in code:
import process from 'node:process';

if (process.permission.has('fs.write', '/tmp')) {
  console.log('Write permission granted to /tmp');
}
```

---

## Production Security Audit Checklist

- [ ] **Run Automated Vulnerability Audits**: Run `npm audit --audit-level=high` in CI pipelines.
- [ ] **Enforce Strict Content Security Policy**: Use `helmet.contentSecurityPolicy()` to mitigate XSS attacks.
- [ ] **Sanitize Prototype Access**: Replace untrusted object dictionaries with `Map` or `Object.create(null)`.
- [ ] **Bypass Shell in Subprocesses**: Always prefer `execFile` and `spawn` with argument arrays over `exec`.
- [ ] **Enforce SameSite Cookies**: Always set `SameSite=Strict; Secure; HttpOnly` on all session cookies to defeat CSRF.
