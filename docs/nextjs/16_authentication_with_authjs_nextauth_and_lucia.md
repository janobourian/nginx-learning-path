# Module 16: Authentication with Auth.js (NextAuth v5) & Role-Based Access Control (RBAC)

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** Security Architecture, OAuth 2.0 & Session Management

---

## 1. The Full-Stack Authentication Landscape in Next.js

Authentication in the Next.js App Router requires handling sessions across four distinct environments:
1. **Server Components**: Checking `await auth()` directly during rendering.
2. **Server Actions**: Verifying user identity before performing database mutations.
3. **Route Handlers**: Authenticating external API requests and Webhooks.
4. **Edge Middleware**: Intercepting incoming requests before they hit pages.

**Auth.js (NextAuth v5)** provides a unified, Edge-compatible authentication engine that works seamlessly across all four environments using a single universal **`auth()`** helper function.

---

## 2. Setting Up Auth.js (NextAuth v5)

```bash
npm install next-auth@beta @auth/prisma-adapter
```

### 1. Master Authentication Config (`src/auth.ts`)

```typescript
// src/auth.ts
import NextAuth from "next-auth";
import GitHub from "next-auth/providers/github";
import Google from "next-auth/providers/google";
import Credentials from "next-auth/providers/credentials";
import { PrismaAdapter } from "@auth/prisma-adapter";
import { db } from "@/lib/db";
import { z } from "zod";
import bcrypt from "bcryptjs";

export const {
  handlers: { GET, POST },
  auth,
  signIn,
  signOut,
} = NextAuth({
  adapter: PrismaAdapter(db),
  session: { strategy: "jwt" }, // Use JWT sessions for Edge Middleware compatibility!
  pages: {
    signIn: "/login",
    error: "/login",
  },
  providers: [
    GitHub({
      clientId: process.env.AUTH_GITHUB_ID,
      clientSecret: process.env.AUTH_GITHUB_SECRET,
    }),
    Google({
      clientId: process.env.AUTH_GOOGLE_ID,
      clientSecret: process.env.AUTH_GOOGLE_SECRET,
    }),
    Credentials({
      name: "credentials",
      credentials: {
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" },
      },
      async authorize(credentials) {
        const parsed = z
          .object({ email: z.string().email(), password: z.string().min(6) })
          .safeParse(credentials);

        if (!parsed.success) return null;

        const user = await db.user.findUnique({
          where: { email: parsed.data.email },
        });

        if (!user || !user.passwordHash) return null;

        const passwordsMatch = await bcrypt.compare(parsed.data.password, user.passwordHash);
        if (!passwordsMatch) return null;

        return {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role, // "admin" | "member"
        };
      },
    }),
  ],
  callbacks: {
    // 1. Attach user ID and Role to the JWT Token:
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id;
        token.role = (user as any).role || "member";
      }
      return token;
    },
    // 2. Expose user ID and Role in the Client/Server Session:
    async session({ session, token }) {
      if (token && session.user) {
        session.user.id = token.id as string;
        (session.user as any).role = token.role as string;
      }
      return session;
    },
  },
});
```

### 2. Route Handler Mounting (`src/app/api/auth/[...nextauth]/route.ts`)

```typescript
// src/app/api/auth/[...nextauth]/route.ts
import { GET, POST } from "@/auth";

export { GET, POST };
```

---

## 3. Consuming Auth in Server Components & Server Actions

### 1. In Server Components (Direct Async Call)

```tsx
// src/app/dashboard/page.tsx
import { auth } from "@/auth";
import { redirect } from "next/navigation";

export default async function DashboardPage() {
  const session = await auth();

  if (!session?.user) {
    redirect("/login?callbackUrl=/dashboard");
  }

  const role = (session.user as any).role;

  return (
    <div>
      <h1>Welcome back, {session.user.name}!</h1>
      <p>Role: <span className="badge">{role}</span></p>
      {role === "admin" && (
        <a href="/admin/system" className="btn-admin">Open Admin Portal</a>
      )}
    </div>
  );
}
```

### 2. In Server Actions (Gatekeeping Mutations)

```typescript
// src/app/actions/projectActions.ts
"use server";

import { auth } from "@/auth";
import { db } from "@/lib/db";
import { revalidatePath } from "next/cache";

export async function deleteProjectAction(projectId: string) {
  const session = await auth();

  // Strict Authorization Check:
  if (!session?.user?.id) {
    throw new Error("Unauthorized: Must be logged in");
  }

  const role = (session.user as any).role;
  if (role !== "admin") {
    throw new Error("Forbidden: Admin privileges required to delete projects");
  }

  await db.project.delete({
    where: { id: projectId },
  });

  revalidatePath("/dashboard/projects");
  return { success: true };
}
```

---

## 4. Edge Middleware Protection with Auth.js

NextAuth v5 allows exporting `auth` as Edge Middleware directly:

```typescript
// src/middleware.ts
export { auth as middleware } from "@/auth";

export const config = {
  matcher: ["/dashboard/:path*", "/admin/:path*"],
};
```

Or with custom redirection logic:

```typescript
// src/middleware.ts
import { auth } from "@/auth";
import { NextResponse } from "next/server";

export default auth((req) => {
  const isLoggedIn = !!req.auth;
  const isProtected = req.nextUrl.pathname.startsWith("/dashboard");

  if (isProtected && !isLoggedIn) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  return NextResponse.next();
});

export const config = {
  matcher: ["/dashboard/:path*"],
};
```

---

## 5. Sign In & Sign Out Buttons

```tsx
// src/components/AuthButtons.tsx
import { signIn, signOut } from "@/auth";

export function SignInWithGitHub() {
  return (
    <form
      action={async () => {
        "use server";
        await signIn("github", { redirectTo: "/dashboard" });
      }}
    >
      <button type="submit" className="btn-github">
        Sign in with GitHub
      </button>
    </form>
  );
}

export function SignOutButton() {
  return (
    <form
      action={async () => {
        "use server";
        await signOut({ redirectTo: "/login" });
      }}
    >
      <button type="submit" className="btn-signout">
        Sign Out
      </button>
    </form>
  );
}
```

---

## Troubleshooting & Best Practices

1. **`AUTH_SECRET` Environment Variable**
   In production, you **must** set `AUTH_SECRET` (generate with `npx auth secret` or `openssl rand -base64 32`) in your environment variables. Without it, session decryption will fail.

2. **Session Strategy for Edge Middleware**
   If you protect routes using Edge Middleware, configure `session: { strategy: 'jwt' }`. Database-backed sessions cannot be queried inside Edge Middleware without HTTP database proxy drivers.
