# Module 10: Route Resolvers, Preloading Strategies & Dynamic Title Strategies

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Routing Optimization, Data Pre-fetching & Preload Strategies

---

## 1. Functional Route Resolvers (`ResolveFn<T>`)

A **Route Resolver** is a function that pre-fetches essential data **before a route transition finishes rendering**.

If a route requires critical initial data to display anything meaningful, using a resolver ensures that the user never sees an empty flashing screen:

```typescript
// src/app/features/projects/resolvers/project.resolver.ts
import { inject } from "@angular/core";
import { type ResolveFn, Router } from "@angular/router";
import { HttpClient } from "@angular/common/http";
import { catchError, of } from "rxjs";

export interface ProjectData {
  id: string;
  name: string;
  budget: number;
}

export const projectResolver: ResolveFn<ProjectData | null> = (route) => {
  const http = inject(HttpClient);
  const router = inject(Router);
  const projectId = route.paramMap.get("projectId");

  if (!projectId) {
    router.navigate(["/not-found"]);
    return of(null);
  }

  return http.get<ProjectData>(`/api/projects/${projectId}`).pipe(
    catchError((error) => {
      console.error("[ProjectResolver Error]:", error);
      // Redirect to error page if project does not exist:
      router.navigate(["/not-found"]);
      return of(null);
    })
  );
};
```

### Attaching the Resolver to Route Configuration:

```typescript
// src/app/features/projects/projects.routes.ts
import { type Routes } from "@angular/router";
import { projectResolver } from "./resolvers/project.resolver";

export const PROJECTS_ROUTES: Routes = [
  {
    path: ":projectId",
    resolve: { project: projectResolver },
    loadComponent: () =>
      import("./project-detail.component").then((m) => m.ProjectDetailComponent),
  },
];
```

### Consuming Resolved Data via Input Signal Binding:

With `withComponentInputBinding()`, resolved data is bound directly to a component `input()` signal matching the resolver key:

```typescript
// src/app/features/projects/project-detail.component.ts
import { Component, input } from "@angular/core";
import { type ProjectData } from "./resolvers/project.resolver";

@Component({
  selector: "app-project-detail",
  standalone: true,
  template: `
    @if (project(); as p) {
      <div class="project-card">
        <h1>{{ p.name }}</h1>
        <p>Budget: ${{ p.budget.toLocaleString() }}</p>
      </div>
    }
  `,
})
export class ProjectDetailComponent {
  // Bound directly from resolver 'project' key!
  public project = input<ProjectData | null>(null);
}
```

---

## 2. Advanced Preloading Strategies

By default, lazy-loaded route chunks (`loadComponent` / `loadChildren`) are downloaded **only when the user clicks a link**. On slow mobile 3G/4G connections, this causes a 1–3 second delay on first navigation.

**Preloading Strategies** download lazy-loaded route JavaScript chunks **in the background after the initial page load has completed**.

```
┌─────────────────────────────────────────────────────────────┐
│                 Preloading Strategy Choices                 │
├──────────────────────────┬──────────────────────────────────┤
│ **NoPreloading**         │ Default. Chunks load strictly on │
│                          │ demand when clicked.             │
├──────────────────────────┼──────────────────────────────────┤
│ **PreloadAllModules**    │ Preloads ALL lazy routes in the  │
│                          │ background immediately on idle.  │
├──────────────────────────┼──────────────────────────────────┤
│ **Custom Network-Aware** │ Preloads only if the user is on  │
│                          │ fast WiFi (skips on 2G/Save-Data)│
└──────────────────────────┴──────────────────────────────────┘
```

### 1. Enabling `PreloadAllModules` in `app.config.ts`

```typescript
// src/app/app.config.ts
import { provideRouter, withPreloading, PreloadAllModules } from "@angular/router";
import { routes } from "./app.routes";

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(
      routes,
      withPreloading(PreloadAllModules) // ◄── Preload all lazy chunks on idle!
    ),
  ],
};
```

---

### 2. Building a Custom Network-Aware Preloading Strategy

To avoid eating users' mobile data on slow connections, inspect the browser's `navigator.connection` API:

```typescript
// src/app/core/routing/network-aware-preloading.strategy.ts
import { Injectable } from "@angular/core";
import { type PreloadingStrategy, type Route } from "@angular/router";
import { Observable, of } from "rxjs";

@Injectable({ providedIn: "root" })
export class NetworkAwarePreloadingStrategy implements PreloadingStrategy {
  preload(route: Route, load: () => Observable<any>): Observable<any> {
    // 1. Check if user enabled "Save-Data" mode in mobile browser:
    const connection = (navigator as any).connection;
    if (connection?.saveData) {
      console.log("[Preload Skipped]: Save-Data is enabled");
      return of(null);
    }

    // 2. Avoid preloading on slow 2G connections:
    const effectiveType = connection?.effectiveType;
    if (effectiveType === "2g" || effectiveType === "slow-2g") {
      console.log(`[Preload Skipped]: Slow connection detected (${effectiveType})`);
      return of(null);
    }

    // 3. Check for custom route data flag (data: { preload: true }):
    if (route.data?.["preload"] === false) {
      return of(null);
    }

    // Preload chunk in background:
    return load();
  }
}
```

---

## 3. Dynamic Page Title Strategy (`TitleStrategy`)

Angular provides a centralized **`TitleStrategy`** to dynamically compute browser tab titles:

```typescript
// src/app/core/routing/template-title.strategy.ts
import { Injectable, inject } from "@angular/core";
import { Title } from "@angular/platform-browser";
import { type RouterStateSnapshot, TitleStrategy } from "@angular/router";

@Injectable({ providedIn: "root" })
export class TemplatePageTitleStrategy extends TitleStrategy {
  private title = inject(Title);

  override updateTitle(snapshot: RouterStateSnapshot): void {
    const pageTitle = this.buildTitle(snapshot);

    if (pageTitle) {
      // Formats as: "Dashboard | Acme Platform"
      this.title.setTitle(`${pageTitle} | Acme Platform`);
    } else {
      this.title.setTitle("Acme Enterprise Platform");
    }
  }
}
```

```typescript
// In app.config.ts:
providers: [
  provideRouter(routes),
  { provide: TitleStrategy, useClass: TemplatePageTitleStrategy },
]
```

---

## Troubleshooting & Best Practices

1. **Resolvers vs Skeletons**
   - Use **Resolvers** when a page *cannot* render without initial data (e.g. edit entity form).
   - Use **Component Skeletons / `@defer`** when you want instant page navigation with progressive loading skeletons (better perceived performance).
