# Module 00: Angular CLI Workspace & Standalone Project Architecture

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Enterprise Toolchain, Workspace Architecture & Modern Angular 17+ Standards

---

## 1. What Is Angular and the Modern "Renaissance"?

**Angular** is a comprehensive, enterprise-grade TypeScript web application platform created by Google. 

Historically known for NgModule complexity and Zone.js change detection overhead, Angular has undergone a massive modern "Renaissance" (Angular 16 through Angular 18+):
1. **Standalone-by-Default Architecture**: NgModules are obsolete. Components, directives, and pipes are standalone, reducing mental overhead and bundle size.
2. **Signals Reactivity**: Fine-grained reactivity powered by a Push/Pull Directed Acyclic Graph (DAG), laying the foundation for **Zoneless Angular**.
3. **Built-in Control Flow**: Native `@if`, `@else`, `@for`, and `@switch` syntax in templates replacing legacy `*ngIf` and `*ngFor`.
4. **Vite & esbuild Build Pipeline**: Lightning-fast local development and sub-second builds replacing legacy Webpack builders.
5. **Modern Hydration & SSR**: Non-destructive hydration with deferred loading (`@defer`).

---

## 2. Setting Up an Angular Workspace (`@angular/cli`)

Install the official Angular CLI globally or run it directly via `npx`:

```bash
# Initialize a modern standalone Angular project with SSR and Tailwind support
npx @angular/cli@latest new my-angular-app -- \
  --standalone \
  --routing \
  --style=css \
  --ssr \
  --package-manager=pnpm

cd my-angular-app
pnpm start
```

### Standard Modern Angular Directory Structure

```
my-angular-app/
├── public/                 ← Static public assets (favicon.ico, robots.txt)
├── src/
│   ├── app/                ← Standalone Component Hierarchy
│   │   ├── core/           ← Singleton services, interceptors, auth guards
│   │   ├── features/       ← Domain feature modules (lazy-loaded standalone routes)
│   │   │   ├── dashboard/
│   │   │   │   ├── dashboard.component.ts
│   │   │   │   ├── dashboard.component.html
│   │   │   │   └── dashboard.routes.ts
│   │   │   └── auth/
│   │   ├── shared/         ← Reusable UI components, pipes, directives
│   │   ├── app.config.ts   ← Application Providers & Configuration
│   │   ├── app.config.server.ts ← Server-Side Rendering Providers
│   │   ├── app.routes.ts   ← Top-level standalone routes
│   │   ├── app.component.ts← Root Application Component
│   │   └── app.component.html
│   ├── main.ts             ← Client browser bootstrap entry point
│   ├── main.server.ts      ← Server-Side SSR bootstrap entry point
│   └── index.html          ← HTML entry point (<app-root></app-root>)
├── angular.json            ← Master CLI workspace build configuration
├── tsconfig.json           ← TypeScript compiler configuration
└── package.json
```

---

## 3. Application Bootstrapping (`main.ts` & `app.config.ts`)

In modern Angular, applications bootstrap directly with `bootstrapApplication` rather than `platformBrowserDynamic().bootstrapModule(AppModule)`:

```typescript
// src/main.ts (Client Entry Point)
import { bootstrapApplication } from "@angular/platform-browser";
import { AppComponent } from "./app/app.component";
import { appConfig } from "./app/app.config";

bootstrapApplication(AppComponent, appConfig).catch((err) =>
  console.error("[Angular Bootstrap Error]:", err)
);
```

```typescript
// src/app/app.config.ts (Dependency Injection & Provider Registry)
import { type ApplicationConfig, provideZoneChangeDetection } from "@angular/core";
import { provideRouter, withComponentInputBinding, withViewTransitions } from "@angular/router";
import { provideHttpClient, withFetch, withInterceptors } from "@angular/common/http";
import { provideClientHydration, withEventReplay } from "@angular/platform-browser";
import { routes } from "./app.routes";
import { authInterceptor } from "./core/interceptors/auth.interceptor";

export const appConfig: ApplicationConfig = {
  providers: [
    // 1. Optimized Change Detection Event Coalescing
    provideZoneChangeDetection({ eventCoalescing: true }),

    // 2. Standalone Router with View Transitions API & input bindings
    provideRouter(routes, withComponentInputBinding(), withViewTransitions()),

    // 3. Modern Fetch-based HttpClient with functional interceptors
    provideHttpClient(withFetch(), withInterceptors([authInterceptor])),

    // 4. Non-Destructive Hydration with Event Replay for SSR
    provideClientHydration(withEventReplay()),
  ],
};
```

---

## 4. The Root Component (`app.component.ts`)

```typescript
// src/app/app.component.ts
import { Component, signal } from "@angular/core";
import { RouterOutlet, RouterLink } from "@angular/router";

@Component({
  selector: "app-root",
  standalone: true, // Explicitly standalone component
  imports: [RouterOutlet, RouterLink],
  template: `
    <div class="app-layout min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <header class="border-b border-slate-800 p-4">
        <nav class="container mx-auto flex justify-between items-center">
          <span class="font-bold text-xl text-indigo-400">Angular Signals Platform</span>
          <div class="flex gap-4">
            <a routerLink="/" class="hover:text-indigo-300">Home</a>
            <a routerLink="/dashboard" class="hover:text-indigo-300">Dashboard</a>
          </div>
        </nav>
      </header>

      <main class="flex-1 container mx-auto p-6">
        <router-outlet />
      </main>

      <footer class="border-t border-slate-800 p-4 text-center text-sm text-slate-500">
        © {{ currentYear() }} Enterprise Angular Platform
      </footer>
    </div>
  `,
  styles: [`
    :host { display: block; }
  `],
})
export class AppComponent {
  public currentYear = signal(new Date().getFullYear());
}
```

---

## 5. Angular CLI Workspace Config (`angular.json`)

Modern Angular uses `@angular-devkit/build-angular:application` powered by **Vite** and **esbuild**:

```json
{
  "$schema": "./node_modules/@angular/cli/lib/config/schema.json",
  "version": 1,
  "projects": {
    "my-angular-app": {
      "projectType": "application",
      "root": "",
      "sourceRoot": "src",
      "prefix": "app",
      "architect": {
        "build": {
          "builder": "@angular-devkit/build-angular:application",
          "options": {
            "outputPath": "dist/my-angular-app",
            "index": "src/index.html",
            "browser": "src/main.ts",
            "server": "src/main.server.ts",
            "prerender": true,
            "ssr": {
              "entry": "server.ts"
            },
            "tsConfig": "tsconfig.app.json",
            "assets": [{ "glob": "**/*", "input": "public" }],
            "styles": ["src/styles.css"],
            "scripts": []
          },
          "configurations": {
            "production": {
              "budgets": [
                { "type": "initial", "maximumWarning": "500kB", "maximumError": "1MB" },
                { "type": "anyComponentStyle", "maximumWarning": "4kB", "maximumError": "8kB" }
              ],
              "outputHashing": "all"
            }
          }
        },
        "serve": {
          "builder": "@angular-devkit/build-angular:dev-server",
          "configurations": {
            "production": { "buildTarget": "my-angular-app:build:production" },
            "development": { "buildTarget": "my-angular-app:build:development" }
          },
          "defaultConfiguration": "development"
        }
      }
    }
  }
}
```

---

## Troubleshooting & Best Practices

1. **Do NOT import `CommonModule` unnecessarily**
   In modern Angular 17+, built-in control flow (`@if`, `@for`) does **not** require importing `CommonModule` or `NgIf`/`NgFor`. Only import specific standalone directives (`RouterOutlet`, `RouterLink`, `FormsModule`) that your component template actually uses.

2. **Always use `provideHttpClient(withFetch())`**
   Configuring `withFetch()` switches Angular's HTTP client from legacy `XMLHttpRequest` to the Web standard `fetch()` API, enabling streaming responses and optimal SSR performance.
