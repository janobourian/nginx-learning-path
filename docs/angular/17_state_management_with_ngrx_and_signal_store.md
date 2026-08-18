# Module 17: State Management with NgRx & `@ngrx/signals` (SignalStore)

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** State Architecture, NgRx & Fine-Grained SignalStore

---

## 1. The Evolution of NgRx: Redux to SignalStore

Historically, enterprise Angular state management relied on the classic **NgRx Redux pattern**:
- Actions (`createAction`), Reducers (`createReducer`), Effects (`createEffect`), Selectors (`createSelector`), and Action Types.
- While robust for large banking apps, the boilerplate was heavy.

In modern Angular, **`@ngrx/signals`** introduces the **SignalStore**:
- **Zero Redux Boilerplate**: No actions, no reducers, no switch-cases.
- **Composable Functional Architecture**: Compose stores using modular feature blocks (`withState`, `withComputed`, `withMethods`, `withHooks`, `withEntities`).
- **100% Native Signals**: Every state slice is automatically exposed as a reactive Signal.

```
Classic NgRx vs Modern SignalStore:
Classic NgRx:
Action ──► Effect ──► Reducer ──► Store ──► Selector Observable ──► Async Pipe (Heavy!)

@ngrx/signals SignalStore:
Component calls Store Method ──► Signal updates directly ──► Component Signal updates! (Zero Boilerplate!)
```

---

## 2. Installing `@ngrx/signals`

```bash
npm install @ngrx/signals
```

---

## 3. Building an Enterprise Store with `@ngrx/signals`

Let's build a fully-featured `ProjectStore` with state, derived computed signals, asynchronous API methods, and lifecycle hooks:

```typescript
// src/app/features/projects/stores/project.store.ts
import { inject } from "@angular/core";
import { HttpClient } from "@angular/common/http";
import {
  signalStore,
  withState,
  withComputed,
  withMethods,
  withHooks,
  patchState,
} from "@ngrx/signals";
import { rxMethod } from "@ngrx/signals/rxjs-interop";
import { computed } from "@angular/core";
import { pipe, switchMap, tap } from "rxjs";
import { tapResponse } from "@ngrx/operators";

export interface Project {
  id: string;
  name: string;
  budget: number;
  status: "active" | "archived";
}

interface ProjectState {
  projects: Project[];
  filter: "all" | "active" | "archived";
  isLoading: boolean;
  error: string | null;
}

const initialState: ProjectState = {
  projects: [],
  filter: "all",
  isLoading: false,
  error: null,
};

export const ProjectStore = signalStore(
  { providedIn: "root" }, // Root singleton provider

  // 1. Base Reactive State
  withState(initialState),

  // 2. Derived Computed Signals (Auto-memoized)
  withComputed(({ projects, filter }) => ({
    filteredProjects: computed(() => {
      const currentFilter = filter();
      const allProjects = projects();

      if (currentFilter === "all") return allProjects;
      return allProjects.filter((p) => p.status === currentFilter);
    }),

    totalBudget: computed(() => {
      return projects().reduce((acc, p) => acc + p.budget, 0);
    }),

    activeCount: computed(() => {
      return projects().filter((p) => p.status === "active").length;
    }),
  })),

  // 3. Store Methods & Asynchronous Operations
  withMethods((store, http = inject(HttpClient)) => ({
    // Synchronous state patch:
    setFilter(newFilter: ProjectState["filter"]): void {
      patchState(store, { filter: newFilter });
    },

    // Asynchronous API call with rxMethod:
    loadProjects: rxMethod<void>(
      pipe(
        tap(() => patchState(store, { isLoading: true, error: null })),
        switchMap(() =>
          http.get<Project[]>("/api/projects").pipe(
            tapResponse({
              next: (projects) => patchState(store, { projects, isLoading: false }),
              error: (error: Error) =>
                patchState(store, { error: error.message, isLoading: false }),
            })
          )
        )
      )
    ),

    // Synchronous mutation:
    archiveProject(projectId: string): void {
      patchState(store, (state) => ({
        projects: state.projects.map((p) =>
          p.id === projectId ? { ...p, status: "archived" as const } : p
        ),
      }));
    },
  })),

  // 4. Lifecycle Hooks (e.g. auto-fetch on store initialization)
  withHooks({
    onInit(store) {
      console.log("[ProjectStore]: Initialized. Loading initial data...");
      store.loadProjects();
    },
    onDestroy(store) {
      console.log("[ProjectStore]: Destroyed.");
    },
  })
);
```

---

## 4. Consuming the SignalStore in Standalone Components

Consuming the SignalStore in components is remarkably clean because the store itself is injected like any regular service:

```typescript
// src/app/features/projects/project-dashboard.component.ts
import { Component, inject } from "@angular/core";
import { ProjectStore } from "./stores/project.store";
import { CurrencyPipe } from "@angular/common";

@Component({
  selector: "app-project-dashboard",
  standalone: true,
  imports: [CurrencyPipe],
  template: `
    <div class="dashboard-shell">
      <header class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">Enterprise Projects</h1>
          <p class="text-slate-400">
            Active: {{ store.activeCount() }} | Total Budget: {{ store.totalBudget() | currency }}
          </p>
        </div>

        <div class="filter-buttons flex gap-2">
          <button (click)="store.setFilter('all')">All</button>
          <button (click)="store.setFilter('active')">Active</button>
          <button (click)="store.setFilter('archived')">Archived</button>
        </div>
      </header>

      @if (store.isLoading()) {
        <div class="loading-spinner">Loading projects...</div>
      }

      @if (store.error(); as err) {
        <div class="alert-error">Failed to load projects: {{ err }}</div>
      }

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        @for (project of store.filteredProjects(); track project.id) {
          <div class="project-card bg-slate-900 border border-slate-800 p-4 rounded-lg">
            <h3 class="font-semibold text-lg">{{ project.name }}</h3>
            <p class="text-sm text-slate-400">Budget: {{ project.budget | currency }}</p>
            <span class="badge" [class.badge-active]="project.status === 'active'">
              {{ project.status }}
            </span>

            @if (project.status === 'active') {
              <button
                (click)="store.archiveProject(project.id)"
                class="mt-4 text-xs text-red-400 hover:underline"
              >
                Archive Project
              </button>
            }
          </div>
        }
      </div>
    </div>
  `,
})
export class ProjectDashboardComponent {
  // Direct injection of the SignalStore:
  public store = inject(ProjectStore);
}
```

---

## 5. Custom Reusable Feature Extensions (`withCallState`)

One of SignalStore's greatest strengths is creating custom modular extensions that can be mixed into any store:

```typescript
// src/app/core/state/with-call-state.feature.ts
import { signalStoreFeature, withState, withComputed } from "@ngrx/signals";
import { computed } from "@angular/core";

export type CallState = "INIT" | "LOADING" | "LOADED" | { error: string };

export function withCallState() {
  return signalStoreFeature(
    withState<{ callState: CallState }>({ callState: "INIT" }),
    withComputed(({ callState }) => ({
      isLoading: computed(() => callState() === "LOADING"),
      isLoaded: computed(() => callState() === "LOADED"),
      error: computed(() => {
        const state = callState();
        return typeof state === "object" ? state.error : null;
      }),
    }))
  );
}

// Now you can mix withCallState() into ANY store:
// export const UserStore = signalStore(withCallState(), withState(...));
```

---

## Troubleshooting & Best Practices

1. **`patchState` Immutability**
   Always use `patchState(store, ...)` to modify state. Never attempt to mutate properties directly (`store.projects().push(...)` is blocked because signals return read-only views).

2. **Component-Scoped Stores**
   To create a store scoped strictly to a single component instance (destroyed when the component unmounts), omit `{ providedIn: 'root' }` and declare the store in the component's `providers: [ProjectStore]`.
