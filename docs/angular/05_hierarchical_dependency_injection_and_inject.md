# Module 05: Hierarchical Dependency Injection & The Functional `inject()` API

**Track:** Angular — Signals Platform & Ivy Architecture
**Category:** Inversion of Control (IoC), Injector Trees & Modern Functional DI

---

## 1. The Angular Hierarchical Injector Tree

Angular features one of the most sophisticated **Hierarchical Dependency Injection (DI)** systems in software engineering. Unlike flat DI containers, Angular organizes injectors into a hierarchical tree that mirrors your component architecture.

```text
Hierarchical Injector Tree:
┌─────────────────────────────────────────────────────────────┐
│                       NullInjector                          │ (Throws 'NullInjectorError: No provider for X!')
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    PlatformInjector                         │ (Shared across multi-apps, e.g. PLATFORM_ID)
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│          RootInjector (EnvironmentInjector)                 │ (Singleton services: @Injectable({ providedIn: 'root' }))
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                  ElementInjector (Parent)                   │ (Component-level providers: @Component({ providers: [...] }))
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                  ElementInjector (Child)                    │ (Local component instance overrides)
└─────────────────────────────────────────────────────────────┘
```

When a component requests a dependency:

1. Angular starts searching at the component's local `ElementInjector`.
2. If not found, it traverses upward to parent element injectors.
3. If not found, it checks the `RootInjector` (`providedIn: 'root'`).
4. If still not found, it reaches `NullInjector` and throws an error (unless marked as optional).

---

## 2. Constructor Injection vs Functional `inject()`

In modern Angular (v14+), the functional **`inject()`** API replaces cumbersome constructor parameter injection:

| Constructor Injection (Legacy) | Functional `inject()` API (Modern) |
| :--- | :--- |
| `constructor(private http: HttpClient, private router: Router) {}` | `private http = inject(HttpClient);`<br>`private router = inject(Router);` |
| Requires calling `super(http, router)` in subclasses | Subclasses inherit injected fields with **zero `super()` boilerplate**! |
| Cannot be used inside standalone helper functions | Enables **Composable Custom DI Functions** |

```typescript
import { Component, inject } from "@angular/core";
import { HttpClient } from "@angular/common/http";
import { Router } from "@angular/router";

@Component({
  selector: "app-dashboard",
  standalone: true,
  template: `<h1>Dashboard</h1>`,
})
export class DashboardComponent {
  // Clean, property-level functional injection:
  private http = inject(HttpClient);
  private router = inject(Router);
}
```

---

## 3. Composable Functional DI Utilities

Because `inject()` can be called inside any function executed within an **Injection Context** (constructors, field initializers, route guards), you can create reusable DI helper composables:

### 1. `injectDestroy()` (Auto-Unsubscribe Helper)

```typescript
// src/app/core/utils/inject-destroy.ts
import { DestroyRef, inject } from "@angular/core";
import { Subject } from "rxjs";

export function injectDestroy(): Subject<void> {
  const destroy$ = new Subject<void>();
  const destroyRef = inject(DestroyRef);

  // Automatically emit and complete when host component destroys:
  destroyRef.onDestroy(() => {
    destroy$.next();
    destroy$.complete();
  });

  return destroy$;
}
```

### 2. `injectRouteParam()` (Type-Safe Route Parameter Extractor)

```typescript
// src/app/core/utils/inject-route-param.ts
import { inject } from "@angular/core";
import { ActivatedRoute } from "@angular/router";
import { toSignal } from "@angular/core/rxjs-interop";
import { map } from "rxjs";

export function injectRouteParam(paramName: string) {
  const route = inject(ActivatedRoute);
  return toSignal(
    route.paramMap.pipe(map((params) => params.get(paramName))),
    { initialValue: null }
  );
}
```

```typescript
// Consuming custom DI utility in a component:
export class UserDetailComponent {
  // Automatically reactive signal of route param ':userId'!
  public userId = injectRouteParam("userId");
}
```

---

## 4. `InjectionToken` & Multi-Providers

When injecting configuration objects, primitives, or abstract interface contracts:

```typescript
// src/app/core/tokens/api-config.token.ts
import { InjectionToken } from "@angular/core";

export interface ApiConfig {
  baseUrl: string;
  timeoutMs: number;
  retryAttempts: number;
}

export const API_CONFIG = new InjectionToken<ApiConfig>("API_CONFIG", {
  providedIn: "root",
  factory: () => ({
    baseUrl: "https://api.example.com/v1",
    timeoutMs: 10000,
    retryAttempts: 3,
  }),
});
```

### Multi-Providers (`multi: true`)

Multi-providers allow multiple providers to contribute to a single token array (used extensively for HTTP interceptors, form validators, and app initializers):

```typescript
export const APP_PLUGINS = new InjectionToken<Plugin[]>("APP_PLUGINS");

// In app.config.ts:
export const appConfig: ApplicationConfig = {
  providers: [
    { provide: APP_PLUGINS, useClass: AnalyticsPlugin, multi: true },
    { provide: APP_PLUGINS, useClass: ErrorTelemetryPlugin, multi: true },
  ],
};

// Consuming the multi-provider array:
export class PluginManagerService {
  private plugins = inject(APP_PLUGINS); // Injected as Plugin[] array!
}
```

---

## 5. Resolution Modifiers in `inject()`

Control how Angular traverses the injector tree using resolution options:

```typescript
import { inject, Host, Optional, Self, SkipSelf } from "@angular/core";

export class CustomControlComponent {
  // 1. optional: Returns null instead of throwing NullInjectorError if not found
  private logger = inject(LoggerService, { optional: true });

  // 2. self: Only look in the local ElementInjector (do not search parent components)
  private localConfig = inject(ComponentConfig, { self: true, optional: true });

  // 3. skipSelf: Skip local ElementInjector and start searching at the parent
  private parentForm = inject(ParentFormGroup, { skipSelf: true });

  // 4. host: Stop searching when reaching the host component boundary
  private hostContainer = inject(HostContainer, { host: true });
}
```

---

## Troubleshooting & Best Practices

1. **`NG0203: inject() must be called from an injection context`**
   `inject()` must be called during component/service instantiation (property initializer or constructor). Calling `inject()` inside an async method, setTimeout, or event click callback will throw an NG0203 error.
   *Fix:* Store the injected service in a class field or capture the `Injector` in the constructor.

2. **Prefer `@Injectable({ providedIn: 'root' })`**
   Tree-shakable root providers guarantee that unused services are automatically stripped from the production build bundle by esbuild/Rollup.
