# Module 01: Security Model & Permissions System

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Runtime Security & Access Control

---

## Deno's Security-First Design

When you run a Node.js script, it immediately has full access to your filesystem, network, environment variables, and the ability to spawn subprocesses. This is convenient but means that `npm install` followed by running the package could silently read your SSH keys, exfiltrate environment variables, or open reverse shell connections.

Deno reverses this default. **Every Deno process runs in a sandbox with zero capabilities by default.** The program cannot read or write files, make network connections, read environment variables, or run subprocesses unless you explicitly grant those permissions when you launch it.

This is not a feature you opt into — it is the only mode Deno operates in.

```bash
# This will fail — no network permission
deno run main.ts

# This succeeds — network explicitly granted
deno run --allow-net main.ts

# This fails at runtime when the code tries to read a file
deno run --allow-net main.ts   # tries Deno.readTextFile() → PermissionDenied error

# This succeeds
deno run --allow-net --allow-read main.ts
```

---

## The Permission Flags

### `--allow-net`

Controls network access: TCP connections, HTTP requests, WebSocket connections. You can restrict it to specific hostnames and ports.

```bash
# Allow all network access
deno run --allow-net main.ts

# Allow connections only to specific hosts
deno run --allow-net=api.example.com,db.internal:5432 main.ts

# Allow connections to any host on port 443
deno run --allow-net=":443" main.ts
```

In code, accessing a disallowed host throws a `Deno.errors.PermissionDenied` error:

```typescript
// With --allow-net=api.example.com only
const response = await fetch("https://other.com/data");
// Throws: PermissionDenied: Requires net access to "other.com:443"
```

### `--allow-read`

Controls filesystem read access. Without this, `Deno.readTextFile()`, `Deno.open()`, and similar APIs fail.

```bash
# Allow reading any file
deno run --allow-read main.ts

# Allow reading only specific directories
deno run --allow-read=/var/data,./config main.ts

# Allow reading a single file
deno run --allow-read=./config.json main.ts
```

### `--allow-write`

Controls filesystem write access. Without this, `Deno.writeTextFile()`, `Deno.create()`, etc. fail.

```bash
# Allow writing to a specific directory only
deno run --allow-write=/tmp/uploads main.ts

# Allow writing anywhere (use with caution)
deno run --allow-write main.ts
```

### `--allow-env`

Controls access to environment variables. Without this, `Deno.env.get()` returns `undefined` and `Deno.env.set()` fails.

```bash
# Allow reading all environment variables
deno run --allow-env main.ts

# Allow only specific variables
deno run --allow-env=DATABASE_URL,API_KEY,PORT main.ts
```

```typescript
// With --allow-env=DATABASE_URL only:
const dbUrl = Deno.env.get("DATABASE_URL");  // works
const secret = Deno.env.get("SECRET_KEY");   // returns undefined (not permitted)
```

### `--allow-run`

Controls subprocess creation via `Deno.Command`. This is one of the most dangerous permissions — a subprocess inherits the parent's permissions.

```bash
# Allow running specific commands only
deno run --allow-run=git,ls main.ts

# Allow running any subprocess
deno run --allow-run main.ts
```

### `--allow-ffi`

Allows loading native shared libraries via `Deno.dlopen()`. This bypasses the security sandbox entirely because native code runs with the process's full OS permissions.

```bash
deno run --allow-ffi main.ts
```

### `--allow-hrtime`

Allows high-resolution time measurement. This is restricted because high-resolution timers can be used for timing side-channel attacks.

```bash
deno run --allow-hrtime main.ts
```

### `-A` / `--allow-all`

Grants all permissions. **Use only in development or trusted scripts.** Never use `-A` in production.

```bash
# Development convenience — disables the sandbox completely
deno run -A main.ts
```

---

## Programmatic Permission Queries

You can check permissions at runtime before attempting an operation:

```typescript
// Check if a permission is granted before using it
const status = await Deno.permissions.query({
  name: "read",
  path: "/etc/passwd",
});

if (status.state === "granted") {
  const content = await Deno.readTextFile("/etc/passwd");
  console.log(content);
} else if (status.state === "prompt") {
  // Permission not yet decided — will prompt if attempted
  console.log("Will prompt for read permission");
} else {
  // state === "denied"
  console.log("Read permission denied");
}
```

Permission states:
- `"granted"` — explicitly allowed via flag
- `"denied"` — explicitly denied via `--deny-*` flag
- `"prompt"` — not yet decided; Deno will ask the user interactively

---

## Interactive Permission Prompts

When you run Deno without permission flags and the code requests a permission, Deno prompts the user:

```
⚠️  ┌ Deno requests read access to "/etc/hosts".
   ├ Requested by `Deno.readTextFile()` API
   ├ Run again with --allow-read to bypass this prompt.
   └ Allow? [y/n/A] (y = yes, allow; n = no, deny; A = allow all read) >
```

This prompt behavior is for development. In production (running without a terminal), or when using `--no-prompt`, unanswered permission requests throw `PermissionDenied` immediately.

---

## Deny Flags — Explicit Revocation

You can grant broad permissions then revoke specific ones:

```bash
# Allow all reads except the /etc directory
deno run --allow-read --deny-read=/etc main.ts

# Allow all network but block connections to internal metadata endpoint
deno run --allow-net --deny-net=169.254.169.254 main.ts
# (169.254.169.254 is the AWS/GCP instance metadata service)
```

This pattern is useful for running third-party scripts with a known-safe permission set.

---

## Handling `PermissionDenied` Errors

```typescript
import { Deno } from "@types/deno";

async function readConfig(path: string): Promise<string | null> {
  try {
    return await Deno.readTextFile(path);
  } catch (error) {
    if (error instanceof Deno.errors.PermissionDenied) {
      console.error(`Permission denied reading: ${path}`);
      console.error("Run with: --allow-read=" + path);
      return null;
    }
    if (error instanceof Deno.errors.NotFound) {
      console.error(`File not found: ${path}`);
      return null;
    }
    throw error;  // Re-throw unexpected errors
  }
}

const config = await readConfig("./config.json");
if (config === null) {
  Deno.exit(1);
}
```

---

## Real-World Permission Configuration for Common Use Cases

### HTTP Server (read config, write logs, accept connections)

```bash
deno run \
  --allow-net=0.0.0.0:8080 \
  --allow-read=./config.json,./public \
  --allow-write=./logs \
  --allow-env=PORT,DATABASE_URL,API_SECRET \
  src/server.ts
```

### Database Migration Script (read schema files, connect to database)

```bash
deno run \
  --allow-read=./migrations,./schema \
  --allow-net=db.internal:5432 \
  --allow-env=DATABASE_URL \
  scripts/migrate.ts
```

### File Processor (read input, write output, no network)

```bash
deno run \
  --allow-read=/data/input \
  --allow-write=/data/output \
  process.ts
```

### CI Script (run git commands, read project files)

```bash
deno run \
  --allow-run=git,deno \
  --allow-read=. \
  --allow-env=CI,GITHUB_TOKEN \
  scripts/ci.ts
```

---

## The `deno.json` `permissions` Field (Deno 2)

In Deno 2, you can specify default permissions in `deno.json` so scripts inherit them without command-line flags:

```json
{
  "tasks": {
    "start": {
      "command": "deno run src/main.ts",
      "permissions": {
        "net": ["api.example.com:443"],
        "read": ["./config.json", "./public"],
        "env": ["PORT", "DATABASE_URL"]
      }
    }
  }
}
```

---

## Permissions at the `deno task` Level

```json
{
  "tasks": {
    "dev": "deno run --watch --allow-net --allow-read --allow-env src/main.ts",
    "test": "deno test --allow-net=localhost:5432 --allow-read=./fixtures tests/",
    "lint": "deno lint",
    "build": "deno compile --allow-net --allow-read --output bin/server src/main.ts"
  }
}
```

Running `deno task dev` automatically applies the flags specified in the task string.

---

## Security Comparison: Deno vs Node.js vs Bun

| Scenario | Node.js | Deno | Bun |
|---|---|---|---|
| Read `/etc/passwd` by default | ✅ Allowed | ❌ PermissionDenied | ✅ Allowed |
| Make network requests by default | ✅ Allowed | ❌ PermissionDenied | ✅ Allowed |
| Read `process.env` by default | ✅ All vars | ❌ Must grant `--allow-env` | ✅ All vars |
| Run child processes by default | ✅ Allowed | ❌ PermissionDenied | ✅ Allowed |
| Supply chain attack surface | All npm code | Sandboxed | All bun code |

The practical implication: when you run `deno run untrusted-script.ts` without flags, the script cannot do anything harmful — it cannot read files, exfiltrate secrets, or call home. The same `node untrusted-script.js` has full access to everything.

---

## Troubleshooting Permission Errors

**`PermissionDenied: Requires read access to "./config.json"`**

Add `--allow-read=./config.json` (or a parent directory) to your run command.

**`PermissionDenied: Requires net access to "api.github.com:443"`**

Add `--allow-net=api.github.com` to your run command. If you want to allow all HTTPS, use `--allow-net`.

**Script works in development but fails in production with permission errors**

Development typically uses `-A` for convenience. In production, enumerate exactly which permissions your script needs. Run with `-A` once, collect all permission-related errors from the application logs, then convert them to specific `--allow-*` flags.

**`error: "--allow-net" flag requires a value`**

This error occurs in some shells if the flag value is empty. Ensure you are not passing an empty string: `--allow-net=` (empty). Omit the `=` entirely for global grant: `--allow-net`.
