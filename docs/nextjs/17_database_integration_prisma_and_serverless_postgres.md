# Module 17: Database Integration — Prisma, Drizzle & Serverless PostgreSQL

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Database Engineering, Connection Pooling & ORM Architecture

---

## 1. The Serverless Database Dilemma in Next.js

In traditional monolithic Node.js servers (e.g. Express), a single server process boots up and maintains a persistent connection pool of 10–20 TCP connections to PostgreSQL or MySQL.

In Next.js serverless and edge hosting (Vercel, AWS Lambda):

- Each incoming user request can spin up an isolated, ephemeral serverless function instance.
- If 1,000 concurrent users hit your site, 1,000 separate Lambda functions spin up simultaneously.
- If each Lambda opens 5 TCP connections, your PostgreSQL database faces **5,000 concurrent connection attempts**, crashing traditional database instances with `FATAL: too many connections`.

```text
Serverless Connection Spikes:
1,000 Concurrent Serverless Functions ──(Direct TCP Connections)──► [Traditional PostgreSQL] (CRASH! 💥)

Serverless Connection Pooling Architecture:
1,000 Serverless Functions ──(HTTP / WebSockets)──► [PgBouncer / Neon Proxy] ──► [PostgreSQL] (Stable! ✅)
```

---

## 2. The Prisma Singleton Pattern (`src/lib/db.ts`)

During local Next.js development, Fast Refresh re-executes module code on every file edit. If you initialize `new PrismaClient()` in module scope, each hot reload instantiates a brand new client, exhausting local database connection limits in seconds.

Use the **Global Singleton Pattern**:

```typescript
// src/lib/db.ts
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const db =
  globalForPrisma.prisma ??
  new PrismaClient({
    log:
      process.env.NODE_ENV === "development"
        ? ["query", "error", "warn"]
        : ["error"],
  });

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = db;
}
```

---

## 3. Designing an Enterprise Prisma Schema (`prisma/schema.prisma`)

```prisma
// prisma/schema.prisma
datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")
  directUrl = env("DIRECT_URL") // Used for migrations bypassing PgBouncer
}

generator client {
  provider = "prisma-client-js"
}

enum Role {
  USER
  ADMIN
  MODERATOR
}

model User {
  id            String      @id @default(cuid())
  name          String?
  email         String      @unique
  passwordHash  String?
  role          Role        @default(USER)
  avatar        String?
  posts         Post[]
  bookmarks     Bookmark[]
  createdAt     DateTime    @default(now())
  updatedAt     DateTime    @updatedAt

  @@index([email])
}

model Post {
  id          String      @id @default(cuid())
  slug        String      @unique
  title       String
  content     String
  published   Boolean     @default(false)
  authorId    String
  author      User        @relation(fields: [authorId], references: [id], onDelete: Cascade)
  bookmarks   Bookmark[]
  createdAt   DateTime    @default(now())
  updatedAt   DateTime    @updatedAt

  @@index([slug])
  @@index([authorId])
}

model Bookmark {
  id        String   @id @default(cuid())
  userId    String
  postId    String
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  post      Post     @relation(fields: [postId], references: [id], onDelete: Cascade)
  createdAt DateTime @default(now())

  @@unique([userId, postId])
  @@index([userId])
}
```

### Running Migrations

```bash

# Generate SQL migration file and apply to database
npx prisma migrate dev --name init_models

# Generate updated TypeScript types
npx prisma generate
```

---

## 4. Atomic Database Transactions in Server Actions

When updating multiple tables (e.g. creating an order and updating inventory counts), use **`db.$transaction`** to guarantee ACID atomicity:

```typescript
// src/app/actions/orderActions.ts
"use server";

import { auth } from "@/auth";
import { db } from "@/lib/db";
import { revalidatePath } from "next/cache";

export async function processOrderTransaction(items: { productId: string; quantity: number }[]) {
  const session = await auth();
  if (!session?.user?.id) throw new Error("Unauthorized");

  const userId = session.user.id;

  // Execute in an atomic transaction:
  const result = await db.$transaction(async (tx) => {
    let totalCents = 0;

    for (const item of items) {
      // 1. Lock product row and verify stock:
      const product = await tx.product.findUnique({
        where: { id: item.productId },
      });

      if (!product || product.stock < item.quantity) {
        throw new Error(`Insufficient inventory for product: ${item.productId}`);
      }

      // 2. Decrement stock:
      await tx.product.update({
        where: { id: item.productId },
        data: { stock: { decrement: item.quantity } },
      });

      totalCents += product.priceCents * item.quantity;
    }

    // 3. Create the Order Record:
    const newOrder = await tx.order.create({
      data: {
        userId,
        totalCents,
        status: "COMPLETED",
        items: {
          create: items.map((i) => ({
            productId: i.productId,
            quantity: i.quantity,
          })),
        },
      },
    });

    return newOrder;
  });

  revalidatePath("/dashboard/orders");
  return { success: true, orderId: result.id };
}
```

---

## 5. Drizzle ORM (Zero-Overhead Alternative to Prisma)

For applications demanding ultra-low query latency and smaller serverless cold starts, **Drizzle ORM** provides SQL-like TypeScript query building:

```typescript
// src/db/schema.ts (Drizzle)
import { pgTable, text, timestamp, boolean } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").unique().notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});
```

```typescript
// src/lib/drizzle.ts
import { drizzle } from "drizzle-orm/neon-http";
import { neon } from "@neondatabase/serverless";
import * as schema from "./schema";

const sql = neon(process.env.DATABASE_URL!);
export const db = drizzle(sql, { schema });

// In Server Component:
// const allUsers = await db.query.users.findMany();
```

---

## Troubleshooting & Best Practices

1. **Direct Database Queries inside Server Components**
   Because Server Components execute strictly on the server, you do **not** need an API layer to query the database. Query `await db.post.findMany()` directly inside your `page.tsx`!

2. **Connection Pooling URLs**
   In serverless clouds (Vercel, Supabase, Neon), configure `DATABASE_URL` to point to the connection pooler port (e.g. `6543` / `?pgbouncer=true`) for application runtime queries, and `DIRECT_URL` (port `5432`) for Prisma CLI schema migrations.
