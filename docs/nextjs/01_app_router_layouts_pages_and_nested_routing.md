# Module 01: App Router — Layouts, Pages, Nested Routing & Special Files

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** File-System Routing, Layouts & Route Interception

---

## 1. The App Router Special File Conventions

In the Next.js App Router, routing is driven by directory structure. Inside each folder, Next.js recognizes a specific set of **reserved file conventions**:

| Special File | Primary Role | Server / Client Default |
| :--- | :--- | :--- |
| **`page.tsx`** | The public UI endpoint for the route | **Server Component** |
| **`layout.tsx`** | Shared shell wrapping child pages; **preserves state across navigation** | **Server Component** |
| **`template.tsx`** | Shared shell that **re-mounts and creates a fresh instance on navigation** | **Server Component** |
| **`loading.tsx`** | Instant loading skeleton automatically wrapped in a `<Suspense>` boundary | **Server Component** |
| **`error.tsx`** | Error boundary catching runtime exceptions in child subtrees | **Client Component (`'use client'`)** |
| **`not-found.tsx`** | UI rendered when `notFound()` is invoked | **Server Component** |
| **`route.ts`** | Backend HTTP API handler (GET, POST, PUT, DELETE) | **Server Node / Edge** |

```
Route Hierarchy & Component Nesting:
<Layout>
  <Template>
    <ErrorBoundary fallback={<Error />}>
      <Suspense fallback={<Loading />}>
        <Page />
      </Suspense>
    </ErrorBoundary>
  </Template>
</Layout>
```

---

## 2. Shared Layouts vs Templates

### 1. Nested Layouts (`layout.tsx`)

Layouts wrap all pages in their folder and subfolders. **Layouts do NOT re-render when navigating between sibling routes**, preserving scroll position, sidebar expansion states, and form inputs:

```tsx
// src/app/dashboard/layout.tsx
import Link from "next/link";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex h-screen">
      <aside className="w-64 bg-slate-900 border-r border-slate-800 p-4 flex flex-col gap-2">
        <h2 className="font-semibold text-lg mb-4">Workspace</h2>
        <Link href="/dashboard" className="p-2 hover:bg-slate-800 rounded">
          Overview
        </Link>
        <Link href="/dashboard/analytics" className="p-2 hover:bg-slate-800 rounded">
          Analytics
        </Link>
        <Link href="/dashboard/settings" className="p-2 hover:bg-slate-800 rounded">
          Settings
        </Link>
      </aside>

      {/* When switching from /dashboard/analytics -> /dashboard/settings,
          the sidebar remains mounted; only children updates! */}
      <section className="flex-1 overflow-auto p-6">{children}</section>
    </div>
  );
}
```

### 2. Templates (`template.tsx`)

Use `template.tsx` instead of `layout.tsx` when you specifically want a fresh instance created on every route change (e.g., logging pageview analytics, triggering enter animations via CSS, or resetting form state).

---

## 3. Dynamic Route Segments

```
Directory Structure:
src/app/
├── blog/
│   └── [slug]/
│       └── page.tsx      ◄── Matches /blog/hello-world, /blog/nextjs-guide
├── shop/
│   └── [...categories]/
│       └── page.tsx      ◄── Catch-All: Matches /shop/clothes, /shop/clothes/shirts/men
└── docs/
    └── [[...slug]]/
        └── page.tsx      ◄── Optional Catch-All: Matches /docs AND /docs/api/v1
```

```tsx
// src/app/blog/[slug]/page.tsx
import { notFound } from "next/navigation";
import { db } from "@/lib/db";

interface PageProps {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}

export default async function BlogPostPage({ params, searchParams }: PageProps) {
  // In Next.js 15+, params and searchParams are asynchronous Promises!
  const { slug } = await params;
  const query = await searchParams;

  const post = await db.post.findUnique({
    where: { slug },
  });

  if (!post) {
    notFound(); // Triggers the nearest not-found.tsx UI!
  }

  return (
    <article className="prose lg:prose-xl dark:prose-invert">
      <h1>{post.title}</h1>
      <p>{post.content}</p>
    </article>
  );
}
```

---

## 4. Route Groups: `(groupName)`

Folders wrapped in parentheses (e.g. `(auth)`, `(marketing)`, `(dashboard)`) are **Route Groups**. 

Route groups allow:
1. **Organizing files without affecting URL paths** (`app/(auth)/login/page.tsx` maps to `/login`, NOT `/auth/login`).
2. **Opting into different root layouts** (e.g. `(auth)` has a minimalist center-card layout, while `(marketing)` has a full header and footer layout).

```
src/app/
├── (auth)/
│   ├── layout.tsx        ← Auth layout (Clean card centered on screen)
│   ├── login/
│   │   └── page.tsx      ← URL: /login
│   └── register/
│       └── page.tsx      ← URL: /register
└── (marketing)/
    ├── layout.tsx        ← Marketing layout (Full navigation & footer)
    ├── about/
    │   └── page.tsx      ← URL: /about
    └── page.tsx          ← URL: / (Homepage)
```

---

## 5. Parallel Routes (`@slot`) & Intercepting Routes (`(.)`)

### 1. Parallel Routes (`@analytics`, `@feed`)

Parallel routes allow rendering multiple independent pages simultaneously within the same layout (ideal for multi-pane dashboards, split screens, or modal dialogs):

```tsx
// src/app/dashboard/layout.tsx
export default function Layout({
  children,
  analytics,
  team,
}: {
  children: React.ReactNode;
  analytics: React.ReactNode; // Injected from app/dashboard/@analytics/page.tsx
  team: React.ReactNode;      // Injected from app/dashboard/@team/page.tsx
}) {
  return (
    <div className="dashboard-grid">
      <main>{children}</main>
      <aside>{analytics}</aside>
      <aside>{team}</aside>
    </div>
  );
}
```

### 2. Intercepting Routes (`(.)`, `(..)`)

Intercepting routes allow loading a route from another part of your app within the current layout (e.g. displaying a photo in a modal overlay when clicking from a feed, while refreshing or sharing the URL directly loads the standalone full photo page):

- `(.)` matches segments on the **same level**.
- `(..)` matches segments **one level above**.
- `(..)(..)` matches segments **two levels above**.
- `(...)` matches segments from the **root `app` directory**.

```
Feed with Modal Photo View:
src/app/
├── feed/
│   ├── (..)photos/[id]/
│   │   └── page.tsx      ◄── Intercepts /photos/:id as a MODAL inside /feed!
│   └── page.tsx
└── photos/
    └── [id]/
        └── page.tsx      ◄── Direct URL visit loads standalone full page!
```

---

## Troubleshooting & Best Practices

1. **`error.tsx` Must Be a Client Component**
   Because error boundaries catch runtime exceptions on the client and provide interactive retry buttons, `error.tsx` **must** declare `'use client'` at the top of the file.

2. **Async `params` in Next.js 15+**
   In Next.js 15, `params` and `searchParams` passed to pages, layouts, and route handlers are **Promises**. Always `await params` before accessing properties.
