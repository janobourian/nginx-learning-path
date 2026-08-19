# Module 06: RxJS Core — Observables, Subjects & Interoperability with Signals

**Track:** Angular — Signals Platform & Ivy Architecture
**Category:** Reactive Streams, Multicasting & Signal Interop

---

## 1. What Is an RxJS Observable?

An **Observable** is a declarative, push-based stream of data that can emit zero, one, or multiple values over time, synchronously or asynchronously.

```text
Observable Lifecycle Stream:
---(next: 1)---(next: 2)---(next: 3)---(error: X)  [Terminated with Error]
---(next: "A")---(next: "B")---(next: "C")---|      [Terminated with Complete]
```

### The Observer Interface

When subscribing to an Observable, an **Observer** object handles three possible notifications:

- **`next(value)`**: Invoked each time the Observable emits a value.
- **`error(err)`**: Invoked if an unhandled exception occurs (terminates stream).
- **`complete()`**: Invoked when the stream finishes emitting (terminates stream).

---

## 2. Cold vs Hot Observables

Understanding the distinction between Cold and Hot Observables is critical for preventing duplicate network requests and managing event broadcasts:

| Criterion | Cold Observable | Hot Observable |
| :--- | :--- | :--- |
| **Producer Location** | Created **inside** the Observable function | Created **outside** the Observable |
| **Execution Trigger** | Producer starts **only when `.subscribe()` is called** | Producer is already running, regardless of subscribers |
| **Multicasting** | **Unicast**: Each subscriber gets a separate, fresh stream | **Multicast**: All subscribers share the same live stream |
| **Examples in Angular** | `HttpClient.get()`, `of()`, `from()`, `interval()` | `Subject`, `BehaviorSubject`, `fromEvent(window, 'click')` |

```typescript
// COLD OBSERVABLE (HttpClient):
// Subscribing twice makes TWO SEPARATE HTTP REQUESTS over the network!
const coldHttp$ = http.get("/api/users");
coldHttp$.subscribe(); // Request 1
coldHttp$.subscribe(); // Request 2
```

---

## 3. The Subject Family: Multicasting & State Management

A **Subject** is both an **Observable** (can be subscribed to) and an **Observer** (has `.next()`, `.error()`, `.complete()` methods). Subjects are the primary mechanism for multicasting in RxJS.

```text
┌─────────────────────────────────────────────────────────────┐
│                       The Subject Family                    │
├────────────────────┬────────────────────────────────────────┤
│ **Subject**        │ Pure event bus. Emits only events that │
│                    │ occur *after* subscription.            │
├────────────────────┼────────────────────────────────────────┤
│ **BehaviorSubject**│ State container. Requires initial value│
│                    │ and replays current `.value` to new    │
│                    │ subscribers immediately.               │
├────────────────────┼────────────────────────────────────────┤
│ **ReplaySubject**  │ Replays the last `N` emitted values    │
│                    │ (buffer window) to new subscribers.    │
├────────────────────┼────────────────────────────────────────┤
│ **AsyncSubject**   │ Emits ONLY the final value when the    │
│                    │ stream calls `.complete()`.            │
└────────────────────┴────────────────────────────────────────┘
```

### 1. `BehaviorSubject` (Classic State Holder Pattern)

```typescript
import { Injectable } from "@angular/core";
import { BehaviorSubject, map } from "rxjs";

export interface UserSession {
  token: string;
  name: string;
}

@Injectable({ providedIn: "root" })
export class SessionService {
  // 1. Private BehaviorSubject holding current state with initial null:
  private sessionSubject$ = new BehaviorSubject<UserSession | null>(null);

  // 2. Public Observable stream exposed to components:
  public session$ = this.sessionSubject$.asObservable();

  // 3. Derived stream:
  public isAuthenticated$ = this.session$.pipe(
    map((session) => Boolean(session?.token))
  );

  // Synchronous snapshot getter:
  public get currentSession(): UserSession | null {
    return this.sessionSubject$.getValue();
  }

  public setSession(session: UserSession): void {
    this.sessionSubject$.next(session);
  }

  public clearSession(): void {
    this.sessionSubject$.next(null);
  }
}
```

---

## 4. Preventing Memory Leaks with `takeUntilDestroyed` (Angular 16+)

In older Angular versions, developers had to manage subscriptions manually with `ngOnDestroy` and `takeUntil(this.destroy$)` to avoid memory leaks.

Modern Angular provides **`takeUntilDestroyed()`**:

```typescript
import { Component, inject } from "@angular/core";
import { takeUntilDestroyed } from "@angular/core/rxjs-interop";
import { interval } from "rxjs";

@Component({
  selector: "app-auto-poller",
  standalone: true,
  template: `<p>Auto Polling Active</p>`,
})
export class AutoPollerComponent {
  constructor() {
    // Automatically unsubscribes when AutoPollerComponent is destroyed!
    interval(1000)
      .pipe(takeUntilDestroyed())
      .subscribe((val) => {
        console.log(`Polling tick: ${val}`);
      });
  }
}
```

---

## 5. Signal and RxJS Interoperability (`@angular/core/rxjs-interop`)

Angular provides high-performance bridge functions to convert between RxJS Observables and Signals seamlessly:

### 1. `toSignal()` (Observable -> Signal)

Converts an Observable into a Signal. Automatically manages the underlying subscription and unsubscription when the component unmounts:

```typescript
import { Component, inject } from "@angular/core";
import { HttpClient } from "@angular/common/http";
import { toSignal } from "@angular/core/rxjs-interop";

export interface SystemMetric {
  cpu: number;
  memory: number;
}

@Component({
  selector: "app-metrics-viewer",
  standalone: true,
  template: `
    @if (metrics(); as m) {
      <p>CPU: {{ m.cpu }}% | Memory: {{ m.memory }}MB</p>
    } @else {
      <p>Loading telemetry...</p>
    }
  `,
})
export class MetricsViewerComponent {
  private http = inject(HttpClient);

  // Convert HttpClient Observable directly to a reactive Signal!
  public metrics = toSignal(this.http.get<SystemMetric>("/api/telemetry"), {
    initialValue: null,
  });
}
```

### 2. `toObservable()` (Signal -> Observable)

Converts a Signal into an RxJS Observable to use operators like `debounceTime`, `switchMap`, or `distinctUntilChanged`:

```typescript
import { Component, signal, inject } from "@angular/core";
import { toObservable } from "@angular/core/rxjs-interop";
import { debounceTime, distinctUntilChanged, switchMap } from "rxjs";
import { HttpClient } from "@angular/common/http";

@Component({
  selector: "app-search-box",
  standalone: true,
  template: `
    <input
      [value]="searchTerm()"
      (input)="updateSearch($event)"
      placeholder="Search..."
    />
  `,
})
export class SearchBoxComponent {
  private http = inject(HttpClient);

  public searchTerm = signal<string>("");

  // Convert Signal to Observable to leverage RxJS debounce operators:
  public searchResults$ = toObservable(this.searchTerm).pipe(
    debounceTime(300),
    distinctUntilChanged(),
    switchMap((query) => this.http.get(`/api/search?q=${query}`))
  );

  public updateSearch(event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.searchTerm.set(value);
  }
}
```

---

## Troubleshooting & Best Practices

1. **`toSignal()` Subscription Timing**
   `toSignal()` subscribes to the Observable **immediately** upon creation (in the injection context), not lazily like the `async` pipe.

2. **Signals vs Observables Decision Framework**

   - Use **Signals** for synchronous UI state, component inputs, and template calculations.
   - Use **RxJS** for asynchronous streaming, event throttling/debouncing, WebSockets, and complex API compositions.
