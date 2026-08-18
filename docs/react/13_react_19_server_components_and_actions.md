# Module 13: React 19 — Server Components (RSC), Server Actions & Form Hooks

**Track:** React — Modern UI & Fiber Architecture  
**Category:** Full-Stack Architecture, Server Components & React 19 Standards

---

## 1. The React 19 Paradigm Shift: React Server Components (RSC)

Historically, all React components were **Client Components**: their JavaScript source code was downloaded by the browser, executed in the browser, and hydrated into DOM nodes.

**React Server Components (RSC)** introduce a new component architecture where components execute **strictly on the server**:

| Feature | React Server Components (RSC) | Client Components (`'use client'`) |
| :--- | :--- | :--- |
| **Execution Environment** | **Server Only** (Node / Bun / Edge) | Server (Initial SSR) + **Browser** (Interactive) |
| **Client Bundle Size** | **Zero KB** (Never sent to the browser) | Included in the client JavaScript bundle |
| **Direct Backend Access** | **Yes** (Direct SQL queries, file system, secrets) | **No** (Must make HTTP API calls) |
| **React Hooks (`useState`, `useEffect`)** | **No** (Stateless execution per request) | **Yes** (Full interactivity) |
| **DOM Event Listeners (`onClick`, `onChange`)**| **No** | **Yes** |

```
┌───────────────────────────────────────────────────────────────┐
│                     Server Component Tree                     │
│  (Direct access to PostgreSQL, Redis, File System, Secrets)   │
│                                                               │
│   <Layout>                                                    │
│     ├── <Sidebar /> (Server: Zero JS sent to client)          │
│     └── <ProductDetail> (Server: Reads DB directly)           │
│           └── <AddToCartButton /> ◄── ['use client' Boundary] │
└───────────────────────────────┬───────────────────────────────┘
                                │ Flight Wire Protocol Stream
                                ▼
┌───────────────────────────────────────────────────────────────┐
│                      Client Browser DOM                       │
│  (Only <AddToCartButton /> JS code is downloaded & hydrated!) │
└───────────────────────────────────────────────────────────────┘
```

---

## 2. The RSC Flight Wire Protocol

Server Components are **not** compiled into HTML strings like traditional SSR. They are compiled into a specialized streaming data format called the **React Flight Wire Protocol**.

The Flight stream describes the virtual component tree, serializing:
- HTML tag layouts
- Props passed to Client Components
- Suspense stream chunks as promises resolve

The browser reconciles this Flight stream directly into the live React Fiber tree **without losing existing client state** (e.g., text typed into input fields is preserved when the server re-renders).

---

## 3. Server Actions (`'use server'`)

**Server Actions** are asynchronous functions defined on the server that can be invoked directly from Client Components or HTML `<form action={...}>` elements. They eliminate the need to manually build separate REST API endpoints (`/api/posts/create`) for mutations.

```typescript
// app/actions/postActions.ts
"use server";

import { db } from "@/lib/db";
import { revalidatePath } from "next/cache";
import { z } from "zod";

const CreatePostSchema = z.object({
  title: z.string().min(3),
  content: z.string().min(10),
});

export async function createPostAction(formData: FormData) {
  const rawTitle = formData.get("title");
  const rawContent = formData.get("content");

  const validated = CreatePostSchema.safeParse({
    title: rawTitle,
    content: rawContent,
  });

  if (!validated.success) {
    return { success: false, errors: validated.error.flatten().fieldErrors };
  }

  // Direct database mutation on the server:
  await db.post.create({
    data: validated.data,
  });

  revalidatePath("/posts");
  return { success: true };
}
```

---

## 4. React 19 Form Hooks: `useActionState` & `useFormStatus`

### 1. `useActionState` (Managing Server Action State & Errors)

`useActionState` wraps a Server Action and manages its return state, pending status, and execution:

```tsx
"use client";

import { useActionState } from "react";
import { createPostAction } from "@/actions/postActions";
import { SubmitButton } from "./SubmitButton";

export function CreatePostForm() {
  // state: return value from server action
  // formAction: enhanced action function passed to <form action={...}>
  // isPending: true while server is executing the action
  const [state, formAction, isPending] = useActionState(createPostAction, {
    success: false,
    errors: {},
  });

  return (
    <form action={formAction} className="post-form">
      <div>
        <label>Title</label>
        <input name="title" required disabled={isPending} />
        {state.errors?.title && <p className="error">{state.errors.title[0]}</p>}
      </div>

      <div>
        <label>Content</label>
        <textarea name="content" required disabled={isPending} />
        {state.errors?.content && <p className="error">{state.errors.content[0]}</p>}
      </div>

      <SubmitButton />
    </form>
  );
}
```

### 2. `useFormStatus` (Context-Aware Child Submit Button)

`useFormStatus` gives any child component inside a `<form>` access to the parent form's pending state without prop drilling:

```tsx
"use client";

import { useFormStatus } from "react-dom";

export function SubmitButton() {
  // Automatically reads the status of the nearest parent <form>!
  const { pending } = useFormStatus();

  return (
    <button type="submit" disabled={pending} className="btn-primary">
      {pending ? "Publishing Post..." : "Publish Post"}
    </button>
  );
}
```

---

## 5. Direct Database Access in Async Server Components

In Server Components, you can write top-level `async/await` directly in the component function:

```tsx
// app/posts/page.tsx (Server Component by default in Next.js App Router / React 19)
import { db } from "@/lib/db";
import { Suspense } from "react";
import { CreatePostForm } from "@/components/CreatePostForm";

export default async function PostsPage() {
  // Direct database query on the server with zero client bundle overhead!
  const posts = await db.post.findMany({
    orderBy: { createdAt: "desc" },
    take: 20,
  });

  return (
    <div className="posts-container">
      <h1>Community Feed</h1>

      <CreatePostForm />

      <section className="feed">
        {posts.map((post) => (
          <article key={post.id} className="post-card">
            <h3>{post.title}</h3>
            <p>{post.content}</p>
          </article>
        ))}
      </section>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Client Boundary Gotcha (`'use client'`)**
   `'use client'` does **not** mean "render only on the client". Client Components are still pre-rendered to HTML on the server during initial SSR. `'use client'` simply marks the boundary where JavaScript code must be included in the browser bundle for interactivity.

2. **Passing Non-Serializable Props across the Server-Client Boundary**
   Props passed from a Server Component to a Client Component must be **JSON-serializable** (strings, numbers, booleans, objects, arrays). You cannot pass functions (unless marked as Server Actions) or class instances across the boundary.