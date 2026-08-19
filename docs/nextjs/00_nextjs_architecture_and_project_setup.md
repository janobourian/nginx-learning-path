# Module 00: Next.js Architecture, App Router Foundations & Project Setup

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Full-Stack Framework Foundations & Toolchain

---

## 1. What Is Next.js and Why Does It Dominate the React Ecosystem?

**Next.js** is a production-grade full-stack framework created by Vercel built on top of React. While vanilla React is a client-side library requiring developers to assemble their own routing, SSR, bundlers, image optimizers, and server environments, Next.js provides a unified, zero-config full-stack platform:

| Capability | Vanilla React (Vite) | Next.js (App Router) |
| :--- | :--- | :--- |
| **Rendering Paradigms** | Client-Side SPA only | **Universal SSR, SSG, ISR, RSC & Streaming** |
| **Routing System** | Manual client-side library (`react-router`) | **File-System App Router** (`app/`) |
| **Server Capabilities** | None (Requires separate backend) | **Built-in Server Actions, Route Handlers & Edge Middleware** |
| **Data Fetching** | Client-side `useEffect` / TanStack Query | **Direct async Server Components & Fetch Cache** |
| **Asset Optimization** | Manual Webpack/Vite plugins | **Built-in `next/image`, `next/font`, `next/script`** |
| **SEO & Social Sharing** | Poor (Requires prerender plugins) | **Automatic dynamic `<head>` metadata & OpenGraph generators** |

---

## 2. The Next.js Paradigm Shift: Pages Router vs App Router

Next.js 13 introduced the **App Router** (built inside the `app/` directory), which fundamentally replaces the legacy **Pages Router** (`pages/` directory):

```text
┌─────────────────────────────────────────────────────────────┐
│                 Legacy Pages Router (pages/)                │
│  • Every component is a Client Component                   │
│  • Data fetching via getServerSideProps / getStaticProps    │
│  • Page-level rendering blocks entire HTML response         │
└─────────────────────────────────────────────────────────────┘
                               ▲
                               │ Architectural Paradigm Shift
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  Modern App Router (app/)                   │
│  • Components are React Server Components (RSC) by default  │
│  • Direct async/await inside components                     │
│  • Streaming HTML with Suspense & selective hydration       │
│  • Nested shared layouts that do not re-render on navigation│
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Scaffolding a Next.js Project (`create-next-app`)

```bash

# Initialize a new Next.js project with App Router and TypeScript
npx create-next-app@latest my-next-app -- \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --src-dir \
  --import-alias "@/*"

cd my-next-app
npm run dev
```

### Standard Next.js Directory Layout (`src/app`)

```text
my-next-app/
├── public/                 ← Static files served at root / (favicon, robots.txt)
├── src/
│   ├── app/                ← App Router File-System Routing Engine
│   │   ├── (auth)/         ← Route Group (omitted from URL path)
│   │   │   ├── login/
│   │   │   │   └── page.tsx
│   │   │   └── register/
│   │   │       └── page.tsx
│   │   ├── dashboard/
│   │   │   ├── layout.tsx  ← Nested shared dashboard layout
│   │   │   ├── page.tsx    ← Dashboard home (/dashboard)
│   │   │   └── loading.tsx ← Instant loading UI skeleton
│   │   ├── api/            ← Backend Route Handlers
│   │   │   └── health/
│   │   │       └── route.ts
│   │   ├── layout.tsx      ← Root Layout (mandatory, contains <html> and <body>)
│   │   ├── page.tsx        ← Root Homepage (/)
│   │   ├── not-found.tsx   ← Global 404 page
│   │   ├── error.tsx       ← Route Error Boundary ('use client')
│   │   └── global.css      ← Global Tailwind / CSS rules
│   ├── components/         ← Reusable UI and Client components
│   ├── lib/                ← Database clients (Prisma), utility functions
│   └── middleware.ts       ← Edge Request Interceptor
├── next.config.ts          ← Next.js compiler & server config
├── tsconfig.json           ← TypeScript configuration
└── package.json
```

---

## 4. The Mandatory Root Layout (`src/app/layout.tsx`)

Every Next.js App Router application **must** define a root `layout.tsx` file at the root of `src/app/`. This file is responsible for defining the top-level `<html>` and `<body>` tags:

```tsx
// src/app/layout.tsx
import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

// Built-in Google Font optimization (Zero layout shift, self-hosted at build time!)
const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

// Dynamic / Static SEO Metadata
export const metadata: Metadata = {
  title: {
    template: "%s | Acme Enterprise",
    default: "Acme Enterprise Platform",
  },
  description: "Next.js Full-Stack Cloud Platform",
  metadataBase: new URL("https://acme.example.com"),
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="bg-slate-950 text-slate-50 antialiased min-h-screen flex flex-col">
        <header className="border-b border-slate-800 p-4">
          <nav className="container mx-auto flex justify-between items-center">
            <span className="font-bold text-xl">Acme Cloud</span>
          </nav>
        </header>

        <main className="flex-1 container mx-auto p-4">{children}</main>

        <footer className="border-t border-slate-800 p-4 text-center text-sm text-slate-500">
          © {new Date().getFullYear()} Acme Corp.
        </footer>
      </body>
    </html>
  );
}
```

---

## 5. Next.js Configuration (`next.config.ts`)

```typescript
// next.config.ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,

  // Standalone output for ultra-minimal Docker container images:
  output: "standalone",

  // Image optimization domain whitelist:
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "images.unsplash.com",
      },
      {
        protocol: "https",
        hostname: "s3.amazonaws.com",
      },
    ],
  },

  // Security Headers:
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        ],
      },
    ];
  },

  // Experimental flags & Turbopack options:
  experimental: {
    serverActions: {
      bodySizeLimit: "2mb",
    },
  },
};

export default nextConfig;
```

---

## Troubleshooting & Best Practices

1. **Root Layout Must Contain `<html>` and `<body>`**
   If you delete `<html>` or `<body>` from `app/layout.tsx`, Next.js will throw a compiler error and inject default HTML wrappers.

2. **Server Components are the Default**
   Files in `app/` are **React Server Components (RSC)** by default. If you need client interactivity (e.g. `useState`, `onClick`, `useEffect`), you must place `'use client'` at the very top of the file.
