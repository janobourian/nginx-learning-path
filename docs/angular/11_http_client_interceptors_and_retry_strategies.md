# Module 11: Functional HTTP Interceptors & Resilient Retry Strategies

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Networking Architecture, Functional Interceptors & HTTP Resilience

---

## 1. The Modern `HttpClient` & Functional Interceptors (Angular 15+)

In modern Angular, `HttpClient` is configured using **`provideHttpClient()`** and **Functional Interceptors (`HttpInterceptorFn`)**, replacing deprecated `HttpClientModule` and class-based `HttpInterceptor` interfaces.

```typescript
// Functional Interceptor Signature:
export type HttpInterceptorFn = (
  req: HttpRequest<unknown>,
  next: HttpHandlerFn
) => Observable<HttpEvent<unknown>>;
```

---

## 2. Production Interceptor Suite

### 1. Authentication & Bearer Token Interceptor

Clones outgoing HTTP requests and attaches the active JWT authentication token:

```typescript
// src/app/core/interceptors/auth.interceptor.ts
import { inject } from "@angular/core";
import { type HttpInterceptorFn } from "@angular/common/http";
import { AuthService } from "../services/auth.service";

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const token = authService.token();

  // Do not attach token for public unauthenticated endpoints
  if (!token || req.url.includes("/api/auth/login")) {
    return next(req);
  }

  // Immutable Request Cloning with Header Injection:
  const clonedRequest = req.clone({
    setHeaders: {
      Authorization: `Bearer ${token}`,
      "X-Client-Version": "2.4.0",
    },
  });

  return next(clonedRequest);
};
```

---

### 2. Global Error Handling & 401 Token Refresh Interceptor

Handles network exceptions, logs telemetry, and intercepts HTTP 401 Unauthorized errors to automatically refresh the session token:

```typescript
// src/app/core/interceptors/error.interceptor.ts
import { inject } from "@angular/core";
import { type HttpInterceptorFn, HttpErrorResponse } from "@angular/common/http";
import { Router } from "@angular/router";
import { catchError, switchMap, throwError } from "rxjs";
import { AuthService } from "../services/auth.service";

export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  return next(req).pipe(
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse) {
        // 1. Handle HTTP 401 Unauthorized (Expired Session)
        if (error.status === 401 && !req.url.includes("/api/auth/refresh")) {
          console.warn("[HTTP 401]: Token expired. Attempting token refresh...");

          return authService.refreshToken().pipe(
            switchMap((newToken) => {
              // Retry original request with fresh token:
              const retriedRequest = req.clone({
                setHeaders: { Authorization: `Bearer ${newToken}` },
              });
              return next(retriedRequest);
            }),
            catchError((refreshErr) => {
              // Refresh failed -> Force logout and redirect
              authService.logout();
              router.navigate(["/login"]);
              return throwError(() => refreshErr);
            })
          );
        }

        // 2. Handle HTTP 403 Forbidden
        if (error.status === 403) {
          console.error("[HTTP 403 Forbidden]: Insufficient permissions");
        }

        // 3. Handle HTTP 500+ Server Errors
        if (error.status >= 500) {
          console.error("[HTTP Server Crash]:", error.message);
        }
      }

      return throwError(() => error);
    })
  );
};
```

---

### 3. Context-Aware In-Memory Caching Interceptor (`HttpContext`)

Use **`HttpContext`** to pass metadata flags from components to interceptors (e.g. opting into client-side caching for specific requests):

```typescript
// src/app/core/http/cache.context.ts
import { HttpContextToken } from "@angular/common/http";

// Token to toggle caching per request:
export const CACHE_ENABLED = new HttpContextToken<boolean>(() => false);
export const CACHE_TTL_MS = new HttpContextToken<number>(() => 60000); // 1 minute default
```

```typescript
// src/app/core/interceptors/cache.interceptor.ts
import { type HttpInterceptorFn, HttpResponse } from "@angular/common/http";
import { of, tap } from "rxjs";
import { CACHE_ENABLED, CACHE_TTL_MS } from "../http/cache.context";

interface CacheEntry {
  response: HttpResponse<unknown>;
  expiry: number;
}

const responseCache = new Map<string, CacheEntry>();

export const cacheInterceptor: HttpInterceptorFn = (req, next) => {
  // Only cache GET requests that explicitly opted-in via HttpContext:
  if (req.method !== "GET" || !req.context.get(CACHE_ENABLED)) {
    return next(req);
  }

  const cached = responseCache.get(req.urlWithParams);
  if (cached && Date.now() < cached.expiry) {
    console.log(`[Cache Hit]: Serving ${req.url} from memory cache`);
    return of(cached.response.clone());
  }

  const ttl = req.context.get(CACHE_TTL_MS);

  return next(req).pipe(
    tap((event) => {
      if (event instanceof HttpResponse) {
        responseCache.set(req.urlWithParams, {
          response: event.clone(),
          expiry: Date.now() + ttl,
        });
      }
    })
  );
};
```

---

## 3. Consuming Caching Interceptors in Services

```typescript
import { Injectable, inject } from "@angular/core";
import { HttpClient, HttpContext } from "@angular/common/http";
import { CACHE_ENABLED, CACHE_TTL_MS } from "@/core/http/cache.context";

@Injectable({ providedIn: "root" })
export class CatalogService {
  private http = inject(HttpClient);

  public getProducts() {
    return this.http.get("/api/products", {
      // Opt into caching for 5 minutes!
      context: new HttpContext()
        .set(CACHE_ENABLED, true)
        .set(CACHE_TTL_MS, 300000),
    });
  }
}
```

---

## 4. Registering Interceptors in `app.config.ts`

Interceptors execute in the **exact order they are declared** in the array:

```typescript
// src/app/app.config.ts
import { type ApplicationConfig } from "@angular/core";
import { provideHttpClient, withFetch, withInterceptors } from "@angular/common/http";
import { authInterceptor } from "./core/interceptors/auth.interceptor";
import { cacheInterceptor } from "./core/interceptors/cache.interceptor";
import { errorInterceptor } from "./core/interceptors/error.interceptor";

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(
      withFetch(),
      withInterceptors([
        authInterceptor,   // 1. Injects Auth Bearer Token
        cacheInterceptor,  // 2. Checks In-Memory Cache
        errorInterceptor,  // 3. Catches Errors & Handles 401 Refresh
      ])
    ),
  ],
};
```

---

## Troubleshooting & Best Practices

1. **`HttpRequest` Immutability**
   `HttpRequest` instances are completely immutable. Never attempt `req.headers.set('key', 'val')`. You must call `req.clone({ setHeaders: { ... } })`.

2. **Always Clone Responses Before Caching**
   Because `HttpResponse` bodies can be consumed by response streams, always clone responses (`event.clone()`) before storing them in memory cache maps.
