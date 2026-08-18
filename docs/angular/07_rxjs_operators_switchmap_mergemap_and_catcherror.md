# Module 07: RxJS Flattening Operators, Error Handling & Composition

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Asynchronous Streams, Flattening Operators & Resilient Pipelines

---

## 1. The Flattening Operator Matrix (Higher-Order Observables)

A **Higher-Order Observable** is an Observable that emits another Observable (`Observable<Observable<T>>`). 

In web development, whenever a user action (e.g. clicking a button or typing in an input) triggers an HTTP request, a higher-order stream is created. **Flattening Operators** determine how concurrent inner Observable streams are resolved:

| Operator | Concurrent Handling Strategy | Cancellation Behavior | Primary Enterprise Use Case |
| :--- | :--- | :--- | :--- |
| **`switchMap`** | **Switch to Newest** | **Cancels previous in-flight request** | Autocomplete search, tab navigation, URL param change |
| **`mergeMap`** | **Concurrent (Parallel)** | Never cancels; all run simultaneously | File batch uploads, bulk independent analytics events |
| **`concatMap`** | **Sequential (Queue)** | Queues each request until previous finishes | Sequential chat message delivery, bank ledger entries |
| **`exhaustMap`** | **Ignore Subsequent** | Ignores incoming triggers until active one completes | Login buttons, payment submit buttons (Prevents double-click!) |

```
Flattening Operator Visual Diagrams:

1. switchMap (Cancels active inner stream on new emission):
Source:  ───A───────B──────────────►
Inner A:    ───1──2─X (Cancelled!)
Inner B:            ───1──2──3─────►
Output:  ──────1───────1──2──3─────►

2. exhaustMap (Drops new emissions while active inner is running):
Source:  ───A───B───C──────────────► (B is IGNORED while A is running!)
Inner A:    ───1──2──3─────────────►
Inner C:                ───1──2────►
Output:  ──────1──2──3─────1──2────►
```

---

## 2. Deep Dive: The 4 Flattening Operators in Angular

### 1. `switchMap` (Typeahead & Search)

```typescript
// Cancels previous in-flight HTTP request if user types a new character:
this.searchInput.valueChanges.pipe(
  debounceTime(300),
  distinctUntilChanged(),
  switchMap((query) => this.http.get(`/api/search?q=${query}`))
);
```

### 2. `exhaustMap` (Login / Payment Submissions)

```typescript
// Prevents duplicate payment submissions if the user rapidly clicks the button 5 times:
this.payButtonClick$.pipe(
  exhaustMap(() => this.http.post("/api/checkout", this.cartPayload))
);
```

### 3. `concatMap` (Deterministic Sequential Order)

```typescript
// Guarantees log messages are written to backend database in exact chronological order:
this.logStream$.pipe(
  concatMap((log) => this.http.post("/api/logs", log))
);
```

### 4. `mergeMap` (Parallel Batch Uploads)

```typescript
// Uploads 10 files concurrently across maximum available network connections:
from(selectedFiles).pipe(
  mergeMap((file) => this.uploadService.uploadFile(file), 4) // Concurrency limit: 4
);
```

---

## 3. Combination Operators: `forkJoin` vs `combineLatest`

### 1. `forkJoin` (Equivalent to `Promise.all`)

Waits for **all passed Observables to complete**, and then emits an object/array with the final emitted values:

```typescript
import { forkJoin } from "rxjs";

export class DashboardDataService {
  public loadDashboardData(userId: string) {
    return forkJoin({
      user: this.http.get<User>(`/api/users/${userId}`),
      roles: this.http.get<string[]>(`/api/users/${userId}/roles`),
      notifications: this.http.get<Notification[]>(`/api/notifications`),
    });
  }
}
```

### 2. `combineLatest` (Live Multi-Stream Synchronization)

Emits a new tuple/object **whenever ANY of the source streams emit a value** (once all streams have emitted at least once):

```typescript
import { combineLatest } from "rxjs";

// Automatically recalculates filtered view whenever filter, pagination, or query changes:
combineLatest([
  this.searchQuery$,
  this.selectedCategory$,
  this.currentPage$,
]).pipe(
  switchMap(([query, category, page]) =>
    this.http.get(`/api/products?q=${query}&cat=${category}&page=${page}`)
  )
);
```

---

## 4. Resilient Error Handling & Retry Strategies

In RxJS, an unhandled error inside a stream **permanently terminates and kills the Observable pipeline**. 

Use **`catchError`** and **`retry`** to build fault-tolerant network pipelines:

```typescript
import { Component, inject } from "@angular/core";
import { HttpClient } from "@angular/common/http";
import { catchError, retry, timer, of, throwError } from "rxjs";

@Component({
  selector: "app-resilient-client",
  standalone: true,
  template: `<p>Resilient Pipeline Active</p>`,
})
export class ResilientClientComponent {
  private http = inject(HttpClient);

  public fetchWithExponentialBackoff() {
    return this.http.get("/api/unstable-service").pipe(
      // Exponential Backoff Retry Strategy (Retry up to 3 times with exponential delay):
      retry({
        count: 3,
        delay: (error, retryCount) => {
          console.warn(`[Network Retry]: Attempt ${retryCount} after error:`, error.message);
          // Delays: 1s, 2s, 4s
          return timer(Math.pow(2, retryCount - 1) * 1000);
        },
      }),

      // Graceful Fallback Error Handler:
      catchError((error) => {
        console.error("[Fatal Stream Error]: All retries exhausted", error);
        // Return a safe fallback value to keep the stream alive for consumers:
        return of({ status: "fallback", data: [] });
      })
    );
  }
}
```

---

## 5. Production Master Example: Real-Time AutoComplete Search Pipeline

```typescript
// src/app/features/search/search-pipeline.service.ts
import { Injectable, inject } from "@angular/core";
import { HttpClient } from "@angular/common/http";
import { FormControl } from "@angular/forms";
import {
  debounceTime,
  distinctUntilChanged,
  filter,
  switchMap,
  catchError,
  map,
  startWith,
} from "rxjs/operators";
import { Observable, of } from "rxjs";

export interface SearchState<T> {
  data: T[];
  isLoading: boolean;
  error: string | null;
}

@Injectable({ providedIn: "root" })
export class SearchPipelineService {
  private http = inject(HttpClient);

  public createSearchStream<T>(
    control: FormControl<string>,
    searchEndpoint: string
  ): Observable<SearchState<T>> {
    return control.valueChanges.pipe(
      // 1. Sanitize query
      map((q) => q.trim()),

      // 2. Debounce keystrokes by 300ms
      debounceTime(300),

      // 3. Prevent duplicate fetches if string hasn't changed
      distinctUntilChanged(),

      // 4. Flatten with switchMap (Cancels stale in-flight requests!)
      switchMap((query) => {
        if (query.length < 2) {
          return of({ data: [], isLoading: false, error: null });
        }

        return this.http.get<T[]>(`${searchEndpoint}?q=${encodeURIComponent(query)}`).pipe(
          map((data) => ({ data, isLoading: false, error: null })),
          // Emit loading state before request resolves:
          startWith({ data: [], isLoading: true, error: null }),
          // Catch errors without killing the outer valueChanges stream:
          catchError((err) =>
            of({ data: [], isLoading: false, error: (err as Error).message })
          )
        );
      }),

      // Initial idle state:
      startWith({ data: [], isLoading: false, error: null })
    );
  }
}
```

---

## Troubleshooting & Best Practices

1. **Placing `catchError` inside `switchMap` vs outside**
   - If `catchError` is placed on the **outer pipe**, an error will catch once and permanently complete (kill) the form input stream.
   - Always place `catchError` inside the **inner pipe (inside `switchMap`)** so errors only catch the individual failing HTTP request without terminating the user's ongoing typing stream.
