# Module 11: Node.js Compatibility Layer & npm Packages

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Ecosystem Migration & Interoperability

---

## Why Deno Supports Node.js Compatibility

Deno's original design excluded Node.js compatibility intentionally — Dahl wanted a clean break from Node's design decisions. However, the npm ecosystem contains hundreds of thousands of packages representing years of engineering effort. Requiring developers to rewrite or find Deno-native alternatives for every package they use was a barrier to adoption.

Deno 1.15 introduced `--compat` mode, and Deno 1.28 introduced the `npm:` specifier — a production-ready Node.js compatibility layer built into the Deno runtime itself. Today, the vast majority of npm packages work in Deno without modification, including packages that use Node.js built-in modules like `node:fs`, `node:path`, `node:crypto`, `node:http`, and `node:stream`.

---

## Using npm Packages with `npm:` Specifier

```typescript
// No installation step — Deno downloads and caches automatically
import express from "npm:express@^4";
import { z } from "npm:zod@^3";
import * as _ from "npm:lodash@^4";
import chalk from "npm:chalk@^5";
import { Redis } from "npm:ioredis@^5";
import { PrismaClient } from "npm:@prisma/client@^5";
import Stripe from "npm:stripe@^16";
```

npm packages are cached in Deno's global cache (`~/.cache/deno/npm/`) — not in a local `node_modules` directory. The first import downloads the package; subsequent runs use the cache.

---

## Node.js Built-in Module Compatibility

Use the `node:` protocol prefix to import Node.js built-in modules:

```typescript
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { promises as fs } from "node:fs";
import path from "node:path";
import { createHash, randomBytes, createHmac } from "node:crypto";
import { EventEmitter } from "node:events";
import { Readable, Writable, Transform } from "node:stream";
import { promisify } from "node:util";
import os from "node:os";
import process from "node:process";
import { Worker, isMainThread, workerData, parentPort } from "node:worker_threads";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import dns from "node:dns/promises";
import { Buffer } from "node:buffer";
```

These are reimplemented by Deno using its own APIs, so they behave like their Node.js equivalents but work within Deno's permission system.

---

## Running Express.js in Deno

```typescript
// express_app.ts
import express from "npm:express@^4";
import cors from "npm:cors@^2";
import helmet from "npm:helmet@^7";
import morgan from "npm:morgan@^1";

const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cors({ origin: "https://app.example.com" }));
app.use(helmet());
app.use(morgan("combined"));

app.get("/", (_req, res) => {
  res.json({ message: "Express running on Deno!" });
});

app.get("/api/users/:id", async (req, res) => {
  const { id } = req.params;
  // Use Deno KV from inside an Express handler
  const kv = await Deno.openKv();
  const user = await kv.get<{ id: string; name: string }>(["users", id]);

  if (!user.value) {
    return res.status(404).json({ error: "User not found" });
  }

  res.json(user.value);
});

app.listen(8080, () => {
  console.log("Express server running on port 8080");
});
```

```bash
deno run --allow-net --allow-env --allow-read express_app.ts
```

---

## Using Prisma ORM with Deno

Prisma requires some extra setup to work with Deno because it generates Node.js-style code:

```prisma
// schema.prisma
generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["deno"]
  output          = "./generated/client"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(uuid())
  email     String   @unique
  name      String
  createdAt DateTime @default(now())
  posts     Post[]
}

model Post {
  id        String   @id @default(uuid())
  title     String
  content   String?
  published Boolean  @default(false)
  author    User     @relation(fields: [authorId], references: [id])
  authorId  String
}
```

```bash

# Generate the Prisma client for Deno
npx prisma generate
```

```typescript
// db.ts
import { PrismaClient } from "./generated/client/deno/edge.ts";

const prisma = new PrismaClient({
  datasourceUrl: Deno.env.get("DATABASE_URL"),
});

// Use Prisma as normal
const users = await prisma.user.findMany({
  where: { posts: { some: { published: true } } },
  include: { posts: { where: { published: true } } },
  orderBy: { createdAt: "desc" },
  take: 10,
});

const newUser = await prisma.user.create({
  data: {
    email: "alice@example.com",
    name: "Alice",
    posts: {
      create: [{ title: "Hello World", published: true }],
    },
  },
});
```

---

## Using ioredis for Redis

```typescript
// redis.ts
import { Redis } from "npm:ioredis@^5";

const redis = new Redis({
  host: Deno.env.get("REDIS_HOST") ?? "localhost",
  port: Number(Deno.env.get("REDIS_PORT") ?? "6379"),
  password: Deno.env.get("REDIS_PASSWORD"),
  retryStrategy: (times: number) => Math.min(times * 100, 3000),
});

// Cache-aside pattern
async function getWithCache<T>(
  key: string,
  ttlSeconds: number,
  fetcher: () => Promise<T>,
): Promise<T> {
  const cached = await redis.get(key);
  if (cached) {
    return JSON.parse(cached) as T;
  }

  const value = await fetcher();
  await redis.setex(key, ttlSeconds, JSON.stringify(value));
  return value;
}

// Usage
const users = await getWithCache(
  "users:active",
  300,
  () => fetchActiveUsersFromDatabase(),
);

async function fetchActiveUsersFromDatabase(): Promise<{ id: string; name: string }[]> {
  return [];  // Replace with actual DB query
}
```

---

## Running Fastify in Deno

```typescript
// fastify_app.ts
import Fastify from "npm:fastify@^4";
import cors from "npm:@fastify/cors@^8";
import rateLimit from "npm:@fastify/rate-limit@^9";
import { z } from "npm:zod@^3";

const app = Fastify({ logger: true });

await app.register(cors, { origin: true });
await app.register(rateLimit, {
  max: 100,
  timeWindow: "1 minute",
});

app.get("/api/health", async () => {
  return { status: "ok", runtime: "deno", version: Deno.version.deno };
});

const CreateUserBody = z.object({
  name: z.string().min(1),
  email: z.string().email(),
});

app.post("/api/users", {
  schema: {
    body: {
      type: "object",
      required: ["name", "email"],
      properties: {
        name: { type: "string" },
        email: { type: "string", format: "email" },
      },
    },
  },
}, async (request, reply) => {
  const body = CreateUserBody.parse(request.body);
  const kv = await Deno.openKv();
  const id = crypto.randomUUID();
  await kv.set(["users", id], { id, ...body, createdAt: new Date() });
  return reply.status(201).send({ id, ...body });
});

await app.listen({ port: 8080, host: "0.0.0.0" });
```

---

## Migrating Node.js Code to Deno

### Mechanical substitutions

| Node.js | Deno equivalent |
| --- | --- |
| `require("fs")` | `import { ... } from "node:fs"` or `Deno.readTextFile()` |
| `require("path")` | `import path from "node:path"` or `@std/path` |
| `__dirname` | `new URL(".", import.meta.url).pathname` |
| `__filename` | `import.meta.url` |
| `process.env.FOO` | `Deno.env.get("FOO")` |
| `process.exit(0)` | `Deno.exit(0)` |
| `process.argv` | `Deno.args` |
| `require("crypto")` | `import { createHash } from "node:crypto"` or `crypto.subtle` |
| `Buffer.from("str")` | `new TextEncoder().encode("str")` |
| `npm install pkg` | Add `"pkg": "npm:pkg@^1"` to `deno.json` imports |

### The `__dirname` Equivalent

```typescript
// Node.js
const configPath = path.join(__dirname, "config.json");

// Deno
import { dirname, fromFileUrl, join } from "@std/path";
const __dirname = dirname(fromFileUrl(import.meta.url));
const configPath = join(__dirname, "config.json");
```

---

## Troubleshooting

### `ReferenceError: require is not defined`

A package is using CommonJS `require()` instead of ESM. Most modern npm packages support both. Try a different version of the package, or look for a Deno/ESM alternative on JSR.

### `Cannot find module 'node:buffer'`

You need Deno 1.28+ for full `node:` protocol support. Run `deno upgrade`.

### Package installs but throws on first function call

Many npm packages use lazy requires internally (require inside a function). This works differently in Deno's CommonJS emulation layer. Open an issue in the package's GitHub repo mentioning Deno compatibility, or switch to a JSR native alternative.

### `package.json` lifecycle scripts (postinstall) don't run

Deno intentionally does not run `postinstall` or other npm lifecycle scripts — they are a common vector for supply chain attacks. If the package requires a postinstall step (like native module compilation), you need to handle that separately or use the `npm:` specifier with a pre-built binary version.
