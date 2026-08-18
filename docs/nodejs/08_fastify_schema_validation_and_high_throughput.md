# Module 08: Fastify Architecture, Schema Compilation & High-Throughput Microservices

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** High-Throughput Frameworks, Schema Compilation & Plugin Architecture

---

## 1. Why Fastify Outperforms Express (Up to 5x Higher Throughput)

While Express remains popular for traditional monolithic apps, **Fastify** has become the gold standard for high-throughput enterprise microservices.

### The 3 Architectural Secrets of Fastify:

1. **`fast-json-stringify` (AOT JSON Serialization)**:
   - Standard `JSON.stringify(obj)` dynamically inspects object types and keys on every request.
   - Fastify takes your JSON Schema at server startup and **compiles a dedicated C++ / V8 JIT serialization function** that concatenates strings in native memory up to **2x–3x faster than `JSON.stringify`**!
2. **`find-my-way` (Radix Tree Router)**:
   - Express uses a linear array of RegExp matchers (O(N) search time).
   - Fastify uses a **Radix Tree (Prefix Trie)** router, matching routes in **O(K) constant time** where K is the URL length.
3. **Encapsulated Plugin Architecture**:
   - Clean dependency graphs with isolated decorator scopes and lifecycle hooks.

```
Routing Performance Comparison:
Express (Linear RegExp Array O(N)):
Matches Route 1 (regex) ──► Route 2 (regex) ──► ... ──► Route 50 (regex) (Slow!)

Fastify (Radix Tree Prefix Trie O(K)):
URL: /api/v1/users/101
Trie: ['api/v1/'] ──► ['users/'] ──► [':id'] (Instant O(K) jump!)
```

---

## 2. Setting Up a Fastify Microservice with TypeScript

```bash
npm install fastify @sinclair/typebox
```

---

## 3. Schema Validation & Serialization with TypeBox

In Fastify, schemas serve two critical roles simultaneously:
1. **Input Validation (Ajv)**: Rejects invalid request payloads with 400 errors *before* the handler runs.
2. **Output Serialization (`fast-json-stringify`)**: Strips unwhitelisted secret fields (like passwords) and accelerates response serialization.

```typescript
// src/features/users/user.schema.ts
import { Type, type Static } from "@sinclair/typebox";

// 1. Request Body Schema:
export const CreateUserBodySchema = Type.Object({
  name: Type.String({ minLength: 2, maxLength: 50 }),
  email: Type.String({ format: "email" }),
  role: Type.Union([Type.Literal("admin"), Type.Literal("member")]),
});

export type CreateUserBody = Static<typeof CreateUserBodySchema>;

// 2. Response Schema (201 Created):
export const UserResponseSchema = Type.Object({
  id: Type.String(),
  name: Type.String(),
  email: Type.String(),
  role: Type.String(),
  createdAt: Type.String(),
});

export type UserResponse = Static<typeof UserResponseSchema>;
```

---

## 4. Feature Route Handler with Pre-Compiled Schemas

```typescript
// src/features/users/user.routes.ts
import { type FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import { CreateUserBodySchema, UserResponseSchema } from "./user.schema";

export const userRoutes: FastifyPluginAsyncTypebox = async (fastify) => {
  fastify.post(
    "/",
    {
      schema: {
        body: CreateUserBodySchema,     // Validates incoming body with Ajv
        response: {
          201: UserResponseSchema,       // Serializes response with fast-json-stringify!
        },
      },
    },
    async (request, reply) => {
      // request.body is 100% strictly typed via TypeBox:
      const { name, email, role } = request.body;

      const newUser = {
        id: `u_${Date.now()}`,
        name,
        email,
        role,
        createdAt: new Date().toISOString(),
      };

      return reply.status(201).send(newUser);
    }
  );

  fastify.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    return { id, name: "Alice Chen", status: "active" };
  });
};
```

---

## 5. The Fastify Lifecycle Hook Sequence

Fastify executes requests through an explicit, predictable lifecycle pipeline:

```
┌─────────────────────────────────────────────────────────────┐
│                 Fastify Request Lifecycle Hooks             │
│                                                             │
│  [Incoming Request]                                         │
│            │                                                │
│            ▼                                                │
│  1. `onRequest` (Headers inspection, rate-limiting)         │
│            │                                                │
│            ▼                                                │
│  2. `preParsing` (Raw payload decompresion)                 │
│            │                                                │
│            ▼                                                │
│  3. `preValidation` (Ajv input validation)                  │
│            │                                                │
│            ▼                                                │
│  4. `preHandler` (Authentication & RBAC guards)             │
│            │                                                │
│            ▼                                                │
│  5. `Handler Function` (Executes business logic)            │
│            │                                                │
│            ▼                                                │
│  6. `preSerialization` (Custom DTO transformation)          │
│            │                                                │
│            ▼                                                │
│  7. `onSend` (Modifies response headers/body)               │
│            │                                                │
│            ▼                                                │
│  8. `onResponse` (Logs access metrics & telemetry)          │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Master Fastify Server (`src/server.ts`)

```typescript
// src/server.ts
import Fastify from "fastify";
import { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import { userRoutes } from "./features/users/user.routes";

const server = Fastify({
  logger: {
    level: "info",
    transport: {
      target: "pino-pretty",
      options: { colorize: true },
    },
  },
  ajv: {
    customOptions: {
      removeAdditional: "all", // Strips malicious extra fields automatically!
      coerceTypes: true,
      useDefaults: true,
    },
  },
}).withTypeProvider<TypeBoxTypeProvider>();

// Register Feature Plugin:
server.register(userRoutes, { prefix: "/api/v1/users" });

// Global Error Handler:
server.setErrorHandler((error, request, reply) => {
  request.log.error(error);

  if (error.validation) {
    return reply.status(400).send({
      error: "Validation Error",
      message: error.message,
      details: error.validation,
    });
  }

  return reply.status(error.statusCode || 500).send({
    error: error.name || "InternalServerError",
    message: error.message,
  });
});

// Start Server:
const start = async () => {
  try {
    const port = Number(process.env.PORT) || 3000;
    await server.listen({ port, host: "0.0.0.0" });
    console.log(`🚀 Fastify High-Throughput Server ready on port ${port}`);
  } catch (err) {
    server.log.error(err);
    process.exit(1);
  }
};

start();
```

---

## Troubleshooting & Best Practices

1. **Always Define `response` Schemas**
   Defining the `response` schema in Fastify routes activates `fast-json-stringify`, boosting serialization speeds by up to 300% and guaranteeing that unwhitelisted sensitive database columns (e.g. `password_hash`) are never leaked to clients.

2. **Use `fastify-plugin` (`fp`) for Global Extensions**
   Fastify encapsulates plugins into isolated scopes by default. If you write a database plugin or auth decorator that must be accessible across *all* sibling routes, wrap it in `import fp from 'fastify-plugin'`.
