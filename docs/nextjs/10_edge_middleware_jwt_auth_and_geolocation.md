# Module 10: Edge Middleware — JWT Authentication, Geolocation & Subdomain Routing

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** Edge Computing, Request Interception & Security Middleware

---

## 1. What Is Next.js Middleware?

**Next.js Middleware** (`src/middleware.ts`) allows you to run code **globally at the Edge before an incoming HTTP request is processed** by the cache, Server Components, or Route Handlers.

Because Middleware runs on the **Edge Runtime** (a lightweight V8 sandbox powered by Web Standards rather than a full Node.js server):
- Middleware executes in **under 5 milliseconds** globally.
- It can redirect, rewrite, modify headers, or inspect cookies before your backend servers ever touch the request.

```
Request Lifecycle with Middleware:
Incoming Request ──► [Edge Middleware (src/middleware.ts)]
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
     [Redirect (307)] [Rewrite URL]  [NextResponse.next()]
     (e.g. to /login) (e.g. Subdomain)      │
                                            ▼
                                   [Data Cache / Route Handler / Page]
```

---

## 2. Matcher Configuration & Path Filtering

Middleware executes on every route by default. Use `config.matcher` to restrict it to specific routes and exclude static assets (`.png`, `.svg`, `_next/static`):

```typescript
// src/middleware.ts
import { NextResponse, type NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  // Middleware logic runs only on matched paths
  return NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - api/public (public endpoints)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico, sitemap.xml, robots.txt
     */
    "/((?!api/public|_next/static|_next/image|favicon.ico|sitemap.xml|robots.txt).*)",
  ],
};
```

---

## 3. JWT Authentication & Edge Token Verification (`jose`)

Because the Edge Runtime does not support Node.js built-ins (`crypto`, `fs`), use the Web Standards-compliant **`jose`** library for verifying JWT tokens:

```bash
npm install jose
```

```typescript
// src/middleware.ts
import { NextResponse, type NextRequest } from "next/server";
import { jwtVerify } from "jose";

const JWT_SECRET = new TextEncoder().encode(
  process.env.JWT_SECRET || "default-secret-key-32-characters-long"
);

// Protected routes pattern
const isProtectedRoute = (path: string) => path.startsWith("/dashboard") || path.startsWith("/admin");
const isAuthRoute = (path: string) => path.startsWith("/login") || path.startsWith("/register");

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const token = request.cookies.get("session_token")?.value;

  let isValidSession = false;
  let userRole = "guest";

  if (token) {
    try {
      // Verify JWT signature directly on the Edge:
      const { payload } = await jwtVerify(token, JWT_SECRET);
      isValidSession = true;
      userRole = (payload.role as string) || "user";
    } catch {
      // Token is expired, malformed, or tampered with
      isValidSession = false;
    }
  }

  // 1. If accessing a protected route without valid session -> Redirect to /login
  if (isProtectedRoute(pathname) && !isValidSession) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("from", pathname); // Preserve destination
    return NextResponse.redirect(loginUrl);
  }

  // 2. Role-Based Access: /admin routes require 'admin' role
  if (pathname.startsWith("/admin") && userRole !== "admin") {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }

  // 3. If authenticated user visits /login -> Redirect to /dashboard
  if (isAuthRoute(pathname) && isValidSession) {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }

  // 4. Inject authenticated user metadata into request headers for downstream Server Components:
  const response = NextResponse.next();
  if (isValidSession) {
    response.headers.set("x-user-role", userRole);
  }

  return response;
}
```

---

## 4. Geolocation & Multi-Region Currency Routing

On platforms like Vercel and Cloudflare, `request.geo` provides geolocation coordinates and country codes:

```typescript
// src/middleware.ts
import { NextResponse, type NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const country = request.geo?.country || "US";
  const city = request.geo?.city || "Unknown";

  const response = NextResponse.next();

  // Forward geolocation data to Server Components:
  response.headers.set("x-user-country", country);
  response.headers.set("x-user-city", city);

  // Set default currency cookie if not set:
  if (!request.cookies.has("preferred_currency")) {
    const currency = country === "GB" ? "GBP" : country === "DE" ? "EUR" : "USD";
    response.cookies.set("preferred_currency", currency);
  }

  return response;
}
```

---

## 5. Multi-Tenant Subdomain Routing (URL Rewrites)

For multi-tenant SaaS platforms where customers have their own subdomains (`acme.app.com` or `custom-domain.com`):

```typescript
// src/middleware.ts
import { NextResponse, type NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const hostname = request.headers.get("host") || "";
  const { pathname } = request.nextUrl;

  // Extract subdomain (e.g. 'acme' from 'acme.platform.com')
  const currentHost = hostname.replace(`.${process.env.NEXT_PUBLIC_ROOT_DOMAIN}`, "");

  // If visiting a tenant subdomain (and not the main marketing root):
  if (currentHost && currentHost !== "platform" && currentHost !== "localhost:3000") {
    // Rewrite URL internally to /tenants/[subdomain]/... without changing browser address bar!
    return NextResponse.rewrite(
      new URL(`/tenants/${currentHost}${pathname}`, request.url)
    );
  }

  return NextResponse.next();
}
```

---

## Troubleshooting & Best Practices

1. **`NextResponse.redirect` vs `NextResponse.rewrite`**
   - `redirect()`: Returns a 307/308 HTTP response; the **browser URL changes**.
   - `rewrite()`: Proxies the request internally to a different route; the **browser URL stays the same** (ideal for A/B testing and subdomains).

2. **Edge Runtime Limitations**
   Middleware cannot connect directly to traditional TCP socket databases (like standard `pg` or `mysql2`). Use HTTP-based serverless drivers (Prisma Accelerate, Neon Serverless, Upstash Redis) or verify JWT signatures locally with `jose`.
