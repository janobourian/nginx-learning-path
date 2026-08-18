# Module 02: Angular Signals & The Push-Pull Reactivity DAG

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Reactivity Internals, Reactive Primitives & Graph Theory

---

## 1. What Is an Angular Signal?

A **Signal** is a wrapper around a value that notifies interested consumers when that value changes. Signals are synchronous, glitch-free, and fine-grained.

Signals solve the foundational limitation of legacy Angular's change detection:
- **Legacy Zone.js**: Monkey-patches all browser async APIs (`setTimeout`, `fetch`, `addEventListener`). Whenever *any* event fires anywhere on the page, Zone.js traverses the **entire component tree from root to leaf** (`ApplicationRef.tick()`) to check if any bindings changed.
- **Signals**: When a signal changes, **only the specific component bindings that read that signal are notified and updated**.

---

## 2. The Push-Pull Directed Acyclic Graph (DAG) Algorithm

Angular Signals use a **Push-Pull Reactivity Algorithm** modeled as a **Directed Acyclic Graph (DAG)**:

```
Reactivity Graph (Diamond Problem Resolution):
            [Signal A: count]
               /         \
              ▼           ▼
      [Computed B: x2]  [Computed C: x3]
              \           /
               ▼         ▼
          [Computed D: B + C]
```

### The Diamond Dependency Problem in Pure Push Systems:
In pure push reactive systems (e.g. RxJS `BehaviorSubject` chains):
1. Signal `A` updates from `1` to `2`.
2. `A` pushes to `B` (`B` becomes `4`).
3. `B` pushes to `D` (`D` computes `4 + 3 = 7` ◄── **GLITCH! Stale C value used!**).
4. `A` pushes to `C` (`C` becomes `6`).
5. `C` pushes to `D` (`D` computes `4 + 6 = 10`).
`D` emitted an intermediate corrupt state (`7`) before reaching its final value (`10`).

### How Angular's Push-Pull DAG Solves This:
1. **Push Phase (Dirty Marking)**: When Signal `A` changes, it sends a lightweight "dirty" notification down the DAG marking `B`, `C`, and `D` as stale. **No computations are executed during this phase.**
2. **Pull Phase (Lazy Evaluation)**: When the UI or an effect requests the value of `D`, `D` pulls from `B` and `C`. `B` and `C` pull from `A`. All values are evaluated in topological order **exactly once**. Zero glitches, zero redundant computations.

---

## 3. The Writable Signal API (`signal()`)

```typescript
import { Component, signal } from "@angular/core";

@Component({
  selector: "app-counter",
  standalone: true,
  template: `
    <div class="counter-card">
      <h2>Count: {{ count() }}</h2>
      <button (click)="increment()">Increment (+1)</button>
      <button (click)="decrement()">Decrement (-1)</button>
      <button (click)="reset()">Reset</button>
      <button (click)="setCustom(100)">Set to 100</button>
    </div>
  `,
})
export class CounterComponent {
  // 1. Initialize a writable signal
  public count = signal<number>(0);

  // 2. Reading a signal: Call it as a function -> count()

  // 3. .set(value): Replaces the value directly
  public setCustom(val: number): void {
    this.count.set(val);
  }

  public reset(): void {
    this.count.set(0);
  }

  // 4. .update(fn): Updates value based on previous state
  public increment(): void {
    this.count.update((prev) => prev + 1);
  }

  public decrement(): void {
    this.count.update((prev) => prev - 1);
  }
}
```

---

## 4. Custom Equality Functions (`equal` option)

By default, Signals use `Object.is(a, b)` to determine if a value has changed. If you update a signal with a value identical to its current state, downstream dependents are **not** marked dirty:

```typescript
import { signal } from "@angular/core";

export interface GeoLocation {
  lat: number;
  lng: number;
}

// Custom deep equality comparator:
export function areCoordsEqual(a: GeoLocation, b: GeoLocation): boolean {
  return a.lat === b.lat && a.lng === b.lng;
}

// Signal with custom equality checker:
export const userLocation = signal<GeoLocation>(
  { lat: 37.7749, lng: -122.4194 },
  { equal: areCoordsEqual }
);

// Setting an identical coordinate object will NOT trigger downstream re-renders:
userLocation.set({ lat: 37.7749, lng: -122.4194 }); // Skipped!
```

---

## 5. Exposing Read-Only Signals (`asReadonly()`)

In enterprise architecture, services should expose **read-only signals** to components to prevent components from mutating internal service state directly:

```typescript
// src/app/core/services/auth.service.ts
import { Injectable, signal } from "@angular/core";

export interface UserProfile {
  id: string;
  name: string;
  role: string;
}

@Injectable({ providedIn: "root" })
export class AuthService {
  // Private writable signal (internal state):
  private _currentUser = signal<UserProfile | null>(null);

  // Public read-only signal (consumers cannot call .set or .update!):
  public readonly currentUser = this._currentUser.asReadonly();

  public login(user: UserProfile): void {
    this._currentUser.set(user);
  }

  public logout(): void {
    this._currentUser.set(null);
  }
}
```

---

## Troubleshooting & Best Practices

1. **Do NOT mutate objects inside `.update()`**
   Always return fresh object and array copies from `.update()`. Mutating properties in-place without changing reference equality will cause default `Object.is` checks to assume nothing changed.

2. **Signals vs RxJS Observables**
   - Use **Signals** for synchronous UI state, derived computations, and template bindings.
   - Use **RxJS Observables** for asynchronous streams, event debouncing, WebSockets, and complex HTTP retry pipelines (Module 06 & 07).
