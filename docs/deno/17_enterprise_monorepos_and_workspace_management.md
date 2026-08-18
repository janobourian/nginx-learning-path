# Module 17: Enterprise Monorepos & Workspace Management

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Project Architecture & Team Collaboration

---

## Deno Workspaces

Deno 2 introduced native workspace support — a feature that lets you manage multiple related packages in a single repository (monorepo) without a separate tool like Lerna or Nx.

A Deno workspace is a root `deno.json` that declares multiple member packages. Each member has its own `deno.json`, its own exports, and can import from other members using their package names.

---

## Workspace Structure

```
my-monorepo/
├── deno.json              ← Root workspace configuration
├── deno.lock              ← Single lockfile for all packages
├── packages/
│   ├── core/              ← Shared business logic
│   │   ├── deno.json
│   │   └── mod.ts
│   ├── api/               ← HTTP API server
│   │   ├── deno.json
│   │   └── main.ts
│   ├── cli/               ← CLI tool
│   │   ├── deno.json
│   │   └── main.ts
│   └── shared-types/      ← Shared TypeScript interfaces
│       ├── deno.json
│       └── mod.ts
└── apps/
    ├── dashboard/         ← Web frontend
    │   └── deno.json
    └── docs-site/
        └── deno.json
```

---

## Root `deno.json` — Workspace Configuration

```json
{
  "workspace": [
    "packages/core",
    "packages/api",
    "packages/cli",
    "packages/shared-types",
    "apps/dashboard"
  ],

  "tasks": {
    "dev:api": "deno task --cwd packages/api dev",
    "dev:cli": "deno task --cwd packages/cli dev",
    "test:all": "deno test --allow-net --allow-read --allow-env packages/ apps/",
    "check:all": "deno check packages/*/mod.ts packages/*/main.ts",
    "fmt": "deno fmt packages/ apps/",
    "lint": "deno lint packages/ apps/",
    "ci": "deno fmt --check && deno lint && deno task check:all && deno task test:all"
  },

  "imports": {
    "@std/assert": "jsr:@std/assert@^1",
    "@std/path": "jsr:@std/path@^1",
    "@std/fs": "jsr:@std/fs@^1",
    "zod": "npm:zod@^3",
    "hono": "jsr:@hono/hono@^4"
  }
}
```

---

## Member Package `deno.json`

```json
// packages/shared-types/deno.json
{
  "name": "@myorg/shared-types",
  "version": "1.0.0",
  "exports": {
    ".": "./mod.ts",
    "./user": "./user.ts",
    "./api": "./api.ts"
  }
}
```

```json
// packages/core/deno.json
{
  "name": "@myorg/core",
  "version": "1.0.0",
  "exports": "./mod.ts",

  "imports": {
    "@myorg/shared-types": "@myorg/shared-types",
    "zod": "npm:zod@^3"
  },

  "tasks": {
    "test": "deno test --allow-env tests/",
    "dev": "deno run --watch --allow-env mod.ts"
  }
}
```

```json
// packages/api/deno.json
{
  "name": "@myorg/api",
  "version": "1.0.0",
  "exports": "./main.ts",

  "imports": {
    "@myorg/core": "@myorg/core",
    "@myorg/shared-types": "@myorg/shared-types",
    "hono": "jsr:@hono/hono@^4",
    "zod": "npm:zod@^3"
  },

  "tasks": {
    "dev": "deno run --watch --allow-net --allow-env --allow-read main.ts",
    "start": "deno run --allow-net --allow-env --allow-read main.ts",
    "test": "deno test --allow-net=localhost --allow-env tests/"
  }
}
```

---

## Cross-Package Imports

Once workspaces are configured, packages import each other by name exactly as they appear in `deno.json`:

```typescript
// packages/core/user_service.ts
import type { User, CreateUserInput } from "@myorg/shared-types";
import { z } from "zod";

const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(100),
  password: z.string().min(8),
});

export class UserService {
  async createUser(input: CreateUserInput): Promise<User> {
    const validated = CreateUserSchema.parse(input);
    // ... business logic
    return {
      id: crypto.randomUUID(),
      ...validated,
      createdAt: new Date(),
    };
  }
}
```

```typescript
// packages/api/routes/users.ts
import { Hono } from "hono";
import { UserService } from "@myorg/core/user_service";  // workspace import
import type { User } from "@myorg/shared-types";

const app = new Hono();
const userService = new UserService();

app.post("/users", async (c) => {
  const body = await c.req.json();
  const user = await userService.createUser(body);
  return c.json(user, 201);
});

export default app;
```

```typescript
// packages/cli/main.ts
import { UserService } from "@myorg/core/user_service";
import { parse } from "@std/flags";

const flags = parse(Deno.args, {
  string: ["email", "name", "password"],
  boolean: ["help"],
});

if (flags.help || !flags.email) {
  console.log("Usage: cli --email=... --name=... --password=...");
  Deno.exit(0);
}

const service = new UserService();
const user = await service.createUser({
  email: flags.email,
  name: flags.name ?? "Unknown",
  password: flags.password ?? "",
});

console.log("Created user:", user.id);
```

---

## Dependency Management Across the Workspace

The root `deno.lock` pins all dependencies for every package in the workspace. This guarantees that:
- All packages use the same version of shared dependencies
- A `deno cache` at the root downloads everything
- CI reproduces exactly the same dependency graph

```bash
# Cache all dependencies for the entire workspace from the root
deno cache packages/api/main.ts packages/cli/main.ts

# Update a dependency across the workspace
# Edit the version in root deno.json, then re-run to update the lock file
deno cache --reload packages/*/mod.ts
```

---

## Versioning and Publishing Strategy

For internal packages that aren't published to JSR:

```bash
# Use git tags to version the entire workspace
git tag v1.2.0
git push origin v1.2.0
```

For packages that are published to JSR:

```bash
# Publish a specific package
cd packages/core
deno publish --dry-run     # Preview what will be published
deno publish               # Publish to JSR
```

For automated publishing via CI:

```yaml
# .github/workflows/publish.yml
name: Publish to JSR

on:
  push:
    tags: ['v*']

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4
      - uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x

      - name: Publish @myorg/shared-types
        working-directory: packages/shared-types
        run: deno publish

      - name: Publish @myorg/core
        working-directory: packages/core
        run: deno publish
```

---

## Running Tasks Across the Workspace

```bash
# Run a task in a specific package
deno task --cwd packages/api dev

# Run tests in all packages
deno test packages/

# Type-check all entry points
deno check packages/api/main.ts packages/cli/main.ts packages/core/mod.ts

# Format the entire monorepo
deno fmt packages/ apps/

# Lint the entire monorepo
deno lint packages/ apps/
```

---

## Docker Multi-Stage Build for a Workspace Package

```dockerfile
# Dockerfile — builds the API package from the workspace
FROM denoland/deno:2.1.4 AS deps

WORKDIR /app

# Copy workspace configuration first (for layer caching)
COPY deno.json deno.lock ./
COPY packages/shared-types/ ./packages/shared-types/
COPY packages/core/ ./packages/core/
COPY packages/api/ ./packages/api/

# Cache dependencies
RUN deno cache packages/api/main.ts

FROM denoland/deno:2.1.4 AS production

WORKDIR /app

COPY --from=deps /root/.cache /root/.cache
COPY --from=deps /app /app

USER deno

EXPOSE 8080
CMD ["run", "--allow-net", "--allow-env=DATABASE_URL,PORT", "packages/api/main.ts"]
```

---

## Troubleshooting

**`Module not found "@myorg/core"`**

The workspace member's `name` in its `deno.json` must match exactly. Check for typos. Also ensure the package directory is listed in the root `deno.json` workspace array.

**Workspace member changes not picked up after edit**

Deno workspaces resolve cross-package imports from the local filesystem — changes are picked up immediately on the next `deno run`. If you're caching aggressively, run `deno cache --reload` on the affected entry point.

**Lock file conflicts in git**

The single `deno.lock` in the root captures all workspace dependencies. When merging branches that updated different packages, merge conflicts in `deno.lock` are resolved by regenerating it: delete `deno.lock`, then run `deno cache packages/api/main.ts packages/cli/main.ts` to regenerate.
