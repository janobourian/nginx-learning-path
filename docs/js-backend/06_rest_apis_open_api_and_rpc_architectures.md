# Module 06: RESTful APIs, OpenAPI 3.1 & RPC Architectures (JSON-RPC & tRPC)

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** API Design, OpenAPI 3.1 Specifications & RPC Protocols

---

## 1. REST vs RPC vs GraphQL Architectural Comparison

| Dimension | RESTful APIs (OpenAPI 3.1) | RPC (JSON-RPC / tRPC / gRPC) | GraphQL |
| :--- | :--- | :--- | :--- |
| **Model** | **Resource-Oriented** (`/users/101`) | **Action/Function-Oriented** (`users.getById`) | Graph Query Language |
| **Transport** | Standard HTTP/1.1 & HTTP/2 | HTTP POST / Binary HTTP/2 | HTTP POST |
| **Schema Standard** | **OpenAPI (Swagger) 3.1** | TypeScript Types / Protobuf | GraphQL Schema Definition |
| **Best For** | Public APIs, microservice integrations | High-velocity full-stack TS apps, internal services | Complex relational client querying |

---

## 2. Generating OpenAPI 3.1 Schemas from Zod Contracts

Instead of manually maintaining separate Swagger YAML files that drift from code, generate OpenAPI schemas directly from **`zod-to-openapi`**:

```javascript
// src/api/contracts/user_contract.js
import { z } from 'zod';
import { extendZodWithOpenApi, OpenApiGeneratorV31 } from '@asteasolutions/zod-to-openapi';

extendZodWithOpenApi(z);

// 1. Define Request DTO with OpenAPI metadata:
export const CreateUserDto = z.object({
  name: z.string().min(2).openapi({ example: 'Alice Chen' }),
  email: z.string().email().openapi({ example: 'alice@acme.com' }),
  role: z.enum(['admin', 'member']).openapi({ example: 'admin' }),
}).openapi('CreateUserDto');

// 2. Define Response DTO:
export const UserResponseDto = z.object({
  id: z.string().openapi({ example: 'u_101' }),
  name: z.string(),
  email: z.string(),
  role: z.string(),
  createdAt: z.string().datetime(),
}).openapi('UserResponseDto');
```

---

## 3. High-Performance JSON-RPC 2.0 Server

**JSON-RPC 2.0** is a standardized, stateless, light-weight remote procedure call specification:

```json
// Example JSON-RPC Request:
{ "jsonrpc": "2.0", "method": "computeTax", "params": { "subtotal": 100, "rate": 0.08 }, "id": 1 }

// Example JSON-RPC Response:
{ "jsonrpc": "2.0", "result": { "tax": 8.0, "total": 108.0 }, "id": 1 }
```

### Pure JavaScript JSON-RPC 2.0 Handler

```javascript
// src/rpc/json_rpc_server.js
import http from 'node:http';

const rpcMethods = {
  // Method 1:
  async ping() {
    return 'pong';
  },

  // Method 2:
  async calculateInvoice({ amount, taxRate }) {
    if (typeof amount !== 'number' || typeof taxRate !== 'number') {
      throw { code: -32602, message: 'Invalid params: amount and taxRate must be numbers' };
    }
    const tax = amount * taxRate;
    return { subtotal: amount, tax, grandTotal: amount + tax };
  },
};

export const jsonRpcServer = http.createServer(async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/rpc') {
    res.writeHead(404);
    res.end();
    return;
  }

  let rawBody = '';
  for await (const chunk of req) rawBody += chunk;

  let requestData;
  try {
    requestData = JSON.parse(rawBody);
  } catch {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ jsonrpc: '2.0', error: { code: -32700, message: 'Parse error' }, id: null }));
    return;
  }

  const { jsonrpc, method, params, id } = requestData;

  if (jsonrpc !== '2.0' || !rpcMethods[method]) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ jsonrpc: '2.0', error: { code: -32601, message: 'Method not found' }, id }));
    return;
  }

  try {
    const result = await rpcMethods[method](params);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ jsonrpc: '2.0', result, id }));
  } catch (err) {
    const errorObj = err.code ? err : { code: -32000, message: err.message };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ jsonrpc: '2.0', error: errorObj, id }));
  }
});
```

---

## 4. End-to-End Type-Safe RPC with tRPC

In TypeScript full-stack architectures (Next.js/React frontend + Node/Deno backend), **tRPC** shares types directly between client and server without code generation or API schema compilation:

```typescript
// Server:
import { initTRPC } from '@trpc/server';
import { z } from 'zod';

const t = initTRPC.create();

export const appRouter = t.router({
  getUser: t.procedure
    .input(z.object({ id: z.string() }))
    .query(async ({ input }) => {
      return { id: input.id, name: 'Alice Chen' };
    }),
});

export type AppRouter = typeof appRouter; // ◄── Exported to client!
```

---

## Troubleshooting & Best Practices

1. **Idempotency Keys on REST Mutations**
   For critical POST payment requests, accept an `Idempotency-Key` header cached in Redis. If a client retries due to network failure, return the cached result instead of double-charging.

2. **Always Use Standard HTTP Status Codes**
   Never return HTTP 200 OK with `{ "error": "Unauthorized" }` in REST APIs. Use real RFC status codes (`400 Bad Request`, `401 Unauthorized`, `403 Forbidden`, `409 Conflict`, `422 Unprocessable Entity`).
