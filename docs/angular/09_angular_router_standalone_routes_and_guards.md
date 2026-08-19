# Module 09: Standalone Angular Router & Functional Route Guards

**Track:** Angular — Signals Platform & Ivy Architecture
**Category:** Client-Side Routing, Lazy Loading & Functional Guards

---

## 1. Modern Standalone Routing Architecture

In modern Angular (v15+), routing is configured using standalone **`Routes`** arrays and functional route guards, completely eliminating `RouterModule.forRoot()` and `RouterModule.forChild()`.

```typescript
// src/app/app.routes.ts
import { type Routes } from "@angular/router";
import { authGuard } from "./core/guards/auth.guard";
import { featureFlagGuard } from "./core/guards/feature-flag.guard";

export const routes: Routes = [
  // 1. Direct Component Route
  {
    path: "",
    loadComponent: () =>
      import("./features/home/home.component").then((m) => m.HomeComponent),
    title: "Home | Angular Signals Platform",
  },

  // 2. Protected Feature Route with Functional Guard
  {
    path: "dashboard",
    canActivate: [authGuard],
    loadComponent: () =>
      import("./features/dashboard/dashboard.component").then((m) => m.DashboardComponent),
    title: "Dashboard",
  },

  // 3. Lazy-Loaded Child Feature Sub-Routes (Code-Split Module)
  {
    path: "projects",
    canMatch: [featureFlagGuard("enable_projects_v2")], // Feature Flag Guard
    loadChildren: () =>
      import("./features/projects/projects.routes").then((m) => m.PROJECTS_ROUTES),
  },

  // 4. Wildcard Catch-All 404 Route
  {
    path: "**",
    loadComponent: () =>
      import("./features/not-found/not-found.component").then((m) => m.NotFoundComponent),
    title: "404 Not Found",
  },
];
```

---

## 2. Functional Route Guards (`CanActivateFn`, `CanMatchFn`, `CanDeactivateFn`)

In legacy Angular, route guards required creating classes that implemented `CanActivate`.

In modern Angular, guards are simple **pure functions** that consume dependencies via `inject()`:

### 1. Authentication & Role Guard (`CanActivateFn`)

```typescript
// src/app/core/guards/auth.guard.ts
import { inject } from "@angular/core";
import { type CanActivateFn, Router } from "@angular/router";
import { AuthService } from "../services/auth.service";

export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (authService.isAuthenticated()) {
    // Check role permissions if specified in route data:
    const requiredRole = route.data?.["role"] as string | undefined;
    if (requiredRole && authService.userRole() !== requiredRole) {
      return router.createUrlTree(["/forbidden"]);
    }
    return true; // Allow navigation
  }

  // Redirect to login and preserve target destination:
  return router.createUrlTree(["/login"], {
    queryParams: { returnUrl: state.url },
  });
};
```

### 2. Unsaved Changes Guard (`CanDeactivateFn`)

Prevents accidental navigation if a user has unsaved edits in a form:

```typescript
// src/app/core/guards/pending-changes.guard.ts
import { type CanDeactivateFn } from "@angular/router";

export interface HasPendingChanges {
  hasUnsavedChanges(): boolean;
}

export const pendingChangesGuard: CanDeactivateFn<HasPendingChanges> = (component) => {
  if (component.hasUnsavedChanges()) {
    return confirm("You have unsaved edits! Do you really want to discard them and leave?");
  }
  return true;
};
```

### 3. Feature Flag Guard (`CanMatchFn`)

`CanMatchFn` evaluates before a route is matched. If it returns `false`, Angular skips this route entirely and tests the next matching route in the array:

```typescript
// src/app/core/guards/feature-flag.guard.ts
import { inject } from "@angular/core";
import { type CanMatchFn } from "@angular/router";
import { FeatureFlagService } from "../services/feature-flag.service";

export function featureFlagGuard(flagKey: string): CanMatchFn {
  return () => {
    const flagService = inject(FeatureFlagService);
    return flagService.isEnabled(flagKey);
  };
}
```

---

## 3. Component Input Binding (`withComponentInputBinding()`)

In modern Angular, you no longer need to inject `ActivatedRoute` to read path parameters, query parameters, or route data.

By enabling `withComponentInputBinding()` in `provideRouter()`, Angular **binds route parameters directly into component inputs / signals**:

```typescript
// src/app/app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(
      routes,
      withComponentInputBinding() // ◄── Enables direct route parameter binding!
    ),
  ],
};
```

### Consuming Route Params Directly as Signal Inputs

Given route path: `/projects/:projectId?tab=analytics`

```typescript
// src/app/features/projects/project-detail.component.ts
import { Component, input, effect } from "@angular/core";

@Component({
  selector: "app-project-detail",
  standalone: true,
  template: `
    <div class="project-view">
      <h2>Project ID: {{ projectId() }}</h2>
      <p>Active Tab: {{ tab() }}</p>
    </div>
  `,
})
export class ProjectDetailComponent {
  // 1. Path parameter ':projectId' bound automatically as a Signal Input!
  public projectId = input.required<string>();

  // 2. Query parameter '?tab=...' bound automatically!
  public tab = input<string>("overview");

  constructor() {
    effect(() => {
      console.log(`Navigated to Project ${this.projectId()}, Tab: ${this.tab()}`);
    });
  }
}
```

---

## 4. Programmatic Navigation & View Transitions API

```typescript
import { Component, inject } from "@angular/core";
import { Router } from "@angular/router";

@Component({
  selector: "app-project-list",
  standalone: true,
  template: `<button (click)="openProject('proj_99')">Open Project</button>`,
})
export class ProjectListComponent {
  private router = inject(Router);

  public openProject(id: string): void {
    this.router.navigate(["/projects", id], {
      queryParams: { tab: "settings" },
      fragment: "general",
    });
  }
}
```

### Native Browser View Transitions API (`withViewTransitions()`)

Enable native animated page transitions by adding `withViewTransitions()` to `provideRouter()`:

```typescript
provideRouter(routes, withViewTransitions());
```

Now, navigating between routes automatically animates with smooth CSS cross-fades!

---

## Troubleshooting & Best Practices

1. **Always Return `UrlTree` for Redirection in Guards**
   In modern guards, return `router.createUrlTree(['/login'])` rather than calling `router.navigate(['/login'])` followed by `return false`. Returning a `UrlTree` cancels the current navigation and starts the new redirect atomically without racing change detection.

2. **`pathMatch: 'full'` on Empty Root Path**
   When defining `{ path: '', redirectTo: '/home', pathMatch: 'full' }`, `pathMatch: 'full'` is mandatory. Without it, the empty prefix matches every URL in the application.
