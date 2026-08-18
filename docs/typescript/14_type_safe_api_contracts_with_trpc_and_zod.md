# Module 14: Type-Safe API Contracts with tRPC & Zod

**Track:** TypeScript — Enterprise Type System  
**Category:** Full-Stack Type Safety, API Contracts & Runtime Validation

---

## 1. The End-to-End Type Safety Dilemma

In traditional client-server web architectures, the type boundary between backend APIs and frontend clients is brittle:

```
[Backend: Node / Go / Python] ──(JSON over HTTP)──► [Frontend: React / Vue / Next.js]
  TypeScript Types: UserDTO                             TypeScript Types: ??? (Manual interface UserDTO)
```

Problems:
1. **Drift**: If the backend renames a field from `userId` to `id`, the frontend types do not fail to compile until runtime.
2. **Double Maintenance**: Maintaining separate backend and frontend DTO interfaces or maintaining complex GraphQL schema codegen pipelines.
3. **Unvalidated JSON**: Casting `await response.json() as UserDTO` performs **zero runtime validation**. If the server returns `{ error: "unauthorized" }`, the client crashes with runtime null pointer exceptions.

**The Solution:** Combining **Zod** (runtime schema validation) with **tRPC** (end-to-end type inference over HTTP without codegen).

---

## 2. Runtime Validation & Type Inference with Zod

**Zod** is a TypeScript-first schema declaration and validation library. You define your data schema once, and TypeScript automatically infers the static type definition using `z.infer<typeof Schema>`:

```typescript
import { z } from "zod";

// 1. Define the Runtime Validation Schema
export const UserRegistrationSchema = z.object({
  username: z
    .string()
    .min(3, "Username must be at least 3 characters")
    .max(20, "Username cannot exceed 20 characters")
    .regex(/^[a-zA-Z0-9_]+$/, "Username must be alphanumeric"),
  email: z.string().email("Invalid email address format"),
  age: z.number().int().min(18, "Must be at least 18 years old").max(120),
  role: z.enum(["admin", "editor", "viewer"]).default("viewer"),
  preferences: z.object({
    newsletter: z.boolean().default(false),
    theme: z.enum(["light", "dark"]).default("dark"),
  }),
});

// 2. Infer the Static TypeScript Type Automatically (Zero Duplication!)
export type UserRegistrationInput = z.infer<typeof UserRegistrationSchema>;
// Inferred as:
// {
//   username: string;
//   email: string;
//   age: number;
//   role: "admin" | "editor" | "viewer";
//   preferences: { newsletter: boolean; theme: "light" | "dark" };
// }
```

### Zod Refinements & Transformations

```typescript
// Transforming string inputs (e.g. from query params or form data)
export const PaginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z
    .string()
    .optional()
    .transform((val) => val?.trim().toLowerCase()),
});

// Refinement: Password confirmation match check
export const ResetPasswordSchema = z
  .object({
    password: z.string().min(8, "Password must be at least 8 characters"),
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"], // Highlight confirmPassword field in form error maps
  });
```

---

## 3. End-to-End Type-Safe RPC with tRPC

**tRPC** allows you to build fully type-safe APIs without code generation, OpenAPI schemas, or runtime GraphQL overhead. Your client imports **only the TypeScript type** of your backend router (`AppRouter`).

```
┌─────────────────────────────────────────────────────────────┐
│                    Backend (tRPC Server)                    │
│                                                             │
│   export const appRouter = router({                         │
│     getUser: procedure.input(z.string()).query(...)         │
│   });                                                       │
│                                                             │
│   export type AppRouter = typeof appRouter; ◄──────────┐    │
└────────────────────────────────────────────────────────┼────┘
                                                         │ Type-Only Import
┌────────────────────────────────────────────────────────┴────┐ (Zero runtime bundle)
│                    Frontend (tRPC Client)                   │
│                                                             │
│   import type { AppRouter } from './server';                │
│   const trpc = createTRPCClient<AppRouter>({ ... });        │
│                                                             │
│   // 100% Autocomplete, Type Checking & Compile-time Safety:│
│   const user = await trpc.getUser.query("u_123");           │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Building the Backend tRPC Router

```typescript
// server/trpc.ts
import { initTRPC, TRPCError } from "@trpc/server";
import { z } from "zod";

export interface Context {
  userId: string | null;
  isAdmin: boolean;
}

const t = initTRPC.context<Context>().create();

export const router = t.router;
export const publicProcedure = t.procedure;

// Protected Procedure Middleware: Enforces authentication
const enforceUserIsAuthed = t.middleware(({ ctx, next }) => {
  if (!ctx.userId) {
    throw new TRPCError({ code: "UNAUTHORIZED", message: "User is not authenticated" });
  }
  return next({
    ctx: {
      userId: ctx.userId,
      isAdmin: ctx.isAdmin,
    },
  });
});

export const protectedProcedure = t.procedure.use(enforceUserIsAuthed);
```

```typescript
// server/routers/app.ts
import { router, publicProcedure, protectedProcedure } from "../trpc.js";
import { UserRegistrationSchema } from "../../shared/schemas.js";
import { z } from "zod";

export const appRouter = router({
  // 1. Public Query Procedure with input validation
  healthCheck: publicProcedure.query(() => {
    return { status: "healthy", uptime: process.uptime() };
  }),

  // 2. Query with parameters: Fetch User
  getUserById: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(async ({ input }) => {
      // Input is strictly typed as { id: string }
      return {
        id: input.id,
        name: "Alice Chen",
        email: "alice@example.com",
        role: "admin" as const,
      };
    }),

  // 3. Mutation Procedure: Create User
  registerUser: publicProcedure
    .input(UserRegistrationSchema)
    .mutation(async ({ input }) => {
      // Input is 100% validated according to UserRegistrationSchema!
      console.log("Registering user in DB:", input.username);

      return {
        id: `usr_${Date.now()}`,
        username: input.username,
        email: input.email,
        createdAt: new Date().toISOString(),
      };
    }),

  // 4. Protected Mutation Procedure
  deleteUser: protectedProcedure
    .input(z.object({ targetUserId: z.string() }))
    .mutation(async ({ input, ctx }) => {
      // ctx.userId is guaranteed to be non-null string!
      console.log(`Admin ${ctx.userId} deleted user ${input.targetUserId}`);
      return { success: true };
    }),
});

// Export ONLY the type definition of the router!
export type AppRouter = typeof appRouter;
```

---

## 5. Consuming the API on the Frontend with Full Autocomplete

```typescript
// client/trpc.ts
import { createTRPCClient, httpBatchLink } from "@trpc/client";
import type { AppRouter } from "../server/routers/app.js";

// Type-safe client initialized using only the AppRouter type:
export const trpc = createTRPCClient<AppRouter>({
  links: [
    httpBatchLink({
      url: "http://localhost:3000/api/trpc",
      headers() {
        return {
          Authorization: `Bearer ${localStorage.getItem("token") || ""}`,
        };
      },
    }),
  ],
});
```

```typescript
// client/app.ts
import { trpc } from "./trpc.js";

async function main() {
  // 1. Full autocomplete for queries:
  const health = await trpc.healthCheck.query();
  console.log("Server health:", health.status);

  // 2. Full autocomplete for inputs and outputs:
  const user = await trpc.getUserById.query({ id: "usr_101" });
  console.log(user.name.toUpperCase()); // user.name is strictly typed as string!

  // 3. Mutation with validated payload:
  const newUser = await trpc.registerUser.mutate({
    username: "alice_dev",
    email: "alice@example.com",
    age: 25,
    role: "admin",
    preferences: {
      newsletter: true,
      theme: "dark",
    },
  });

  console.log("Created user ID:", newUser.id);

  // ❌ If you pass an invalid property or invalid type, TypeScript catches it instantly:
  // await trpc.registerUser.mutate({ username: "al" }); // Error: Property 'email' is missing!
}

main();
```

---

## Troubleshooting & Best Practices

1. **Type-Only Imports for Client Code**
   Always use `import type { AppRouter } from '...'` on the client. This guarantees that zero backend server code or database drivers are bundled into the client browser build.

2. **Zod Parsing Performance**
   In high-throughput microservices handling 50,000+ requests/sec, pre-compile hot schemas or use `safeParse()` instead of `parse()` to avoid exception allocation overhead in V8.
