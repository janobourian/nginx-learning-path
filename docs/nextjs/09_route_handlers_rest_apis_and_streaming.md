# Module 09: Route Handlers — REST APIs, Streaming & SSE

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Backend Endpoints, HTTP Route Handlers & Data Streaming

---

## 1. What Are Route Handlers?

**Route Handlers** allow you to create custom HTTP request endpoints using Web standard `Request` and `Response` APIs inside the App Router. They replace the legacy `pages/api` handlers.

Route handlers are defined in **`route.ts`** files inside the `src/app/` directory and support the following HTTP method exports:
`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, and `OPTIONS`.

```text
File Location Mapping:
src/app/api/users/route.ts       ──► URL: /api/users
src/app/api/users/[id]/route.ts  ──► URL: /api/users/:id
src/app/api/webhook/stripe/route.ts ──► URL: /api/webhook/stripe
```

---

## 2. Standard REST API Implementation (`GET`, `POST`, `DELETE`)

```typescript
// src/app/api/users/[id]/route.ts
import { type NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { z } from "zod";

const UpdateUserSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
});

interface RouteParams {
  params: Promise<{ id: string }>;
}

// 1. GET: Fetch User by ID
export async function GET(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;

  const user = await db.user.findUnique({
    where: { id },
    select: { id: true, name: true, email: true, createdAt: true },
  });

  if (!user) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true, data: user });
}

// 2. PATCH: Update User
export async function PATCH(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;

  try {
    const rawBody = await request.json();
    const validated = UpdateUserSchema.safeParse(rawBody);

    if (!validated.success) {
      return NextResponse.json(
        { error: "Validation Error", details: validated.error.flatten() },
        { status: 400 }
      );
    }

    const updatedUser = await db.user.update({
      where: { id },
      data: validated.data,
    });

    return NextResponse.json({ success: true, data: updatedUser });
  } catch (error) {
    return NextResponse.json(
      { error: "Internal Server Error", message: (error as Error).message },
      { status: 500 }
    );
  }
}

// 3. DELETE: Remove User
export async function DELETE(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;

  await db.user.delete({ where: { id } });

  return new NextResponse(null, { status: 204 }); // 204 No Content
}
```

---

## 3. Streaming Responses & Server-Sent Events (SSE)

Route Handlers support Web standard **`ReadableStream`** for real-time data streaming and Server-Sent Events (SSE):

```typescript
// src/app/api/stream/sse/route.ts
import { type NextRequest } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      // Send initial connection event
      controller.enqueue(encoder.encode(`data: ${JSON.stringify({ status: "connected" })}\n\n`));

      // Stream live telemetry updates every second:
      let ticks = 0;
      const interval = setInterval(() => {
        ticks++;
        const telemetry = {
          cpuUsage: (Math.random() * 100).toFixed(1),
          memoryUsageMb: Math.round(500 + Math.random() * 200),
          timestamp: new Date().toISOString(),
        };

        controller.enqueue(encoder.encode(`data: ${JSON.stringify(telemetry)}\n\n`));

        if (ticks >= 10) {
          clearInterval(interval);
          controller.close();
        }
      }, 1000);

      // Clean up interval when client disconnects
      request.signal.addEventListener("abort", () => {
        clearInterval(interval);
      });
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
```

---

## 4. Streaming AI Completions (LLM Chunked Streaming)

```typescript
// src/app/api/chat/stream/route.ts
import { type NextRequest } from "next/server";

export const runtime = "edge"; // Run on Edge for lowest TTFB latency

export async function POST(request: NextRequest) {
  const { prompt } = await request.json();

  const encoder = new TextEncoder();

  // Simulated AI Token Stream:
  const textTokens = `Here is your detailed analysis for: "${prompt}". Next.js streaming enables instant token delivery!`.split(" ");

  const stream = new ReadableStream({
    async start(controller) {
      for (const token of textTokens) {
        controller.enqueue(encoder.encode(token + " "));
        // Simulate token generation latency:
        await new Promise((r) => setTimeout(r, 60));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Transfer-Encoding": "chunked",
    },
  });
}
```

---

## 5. Handling CORS in Route Handlers

If your Route Handler is consumed by external mobile apps or third-party web domains:

```typescript
// src/app/api/public/data/route.ts
import { type NextRequest, NextResponse } from "next/server";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

// Handle Preflight OPTIONS request
export async function OPTIONS() {
  return new NextResponse(null, {
    status: 204,
    headers: CORS_HEADERS,
  });
}

export async function GET() {
  return NextResponse.json(
    { message: "Public Data API" },
    { headers: CORS_HEADERS }
  );
}
```

---

## Troubleshooting & Best Practices

1. **Route Handlers vs Server Actions**

   - Use **Server Actions** for form mutations, dashboard interactions, and mutations originating from within your Next.js application.
   - Use **Route Handlers** when you need a public webhook endpoint (Stripe, GitHub), an external REST API for mobile clients, or streaming SSE/LLM tokens.

2. **`route.ts` and `page.tsx` Conflict**
   You cannot have a `route.ts` and a `page.tsx` in the **same directory folder** (e.g. `app/dashboard/page.tsx` and `app/dashboard/route.ts` will conflict). Move API routes into `app/api/...`.
