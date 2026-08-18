# Module 03: Computed Signals, Reactive Effects & Dependency Tracking

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Derived Reactivity, Side Effects & Dynamic Dependency Tracking

---

## 1. Computed Signals (`computed()`)

A **Computed Signal** represents a derived, read-only reactive value calculated from one or more dependency signals:

```typescript
const derivedSignal = computed(() => expression);
```

### Key Characteristics of `computed()`:
1. **Lazy Evaluation**: The calculation function is **never executed until the computed signal is actively read** by a template or effect.
2. **Memoization**: Once calculated, the result is cached. Subsequent reads return the cached value instantly without re-evaluating the function until dependencies change.
3. **Pure & Read-Only**: Computed signals cannot be manually modified via `.set()` or `.update()`.

```typescript
import { Component, signal, computed } from "@angular/core";

@Component({
  selector: "app-pricing-calculator",
  standalone: true,
  template: `
    <div>
      <p>Base Price: ${{ basePrice() }}</p>
      <p>Quantity: {{ quantity() }}</p>
      <p>Subtotal: ${{ subtotal() }}</p>
      <p>Sales Tax (8%): ${{ tax() }}</p>
      <h3>Total Amount: ${{ total() }}</h3>
    </div>
  `,
})
export class PricingCalculatorComponent {
  public basePrice = signal<number>(100);
  public quantity = signal<number>(2);

  // Derived computed values:
  public subtotal = computed(() => this.basePrice() * this.quantity());
  public tax = computed(() => Number((this.subtotal() * 0.08).toFixed(2)));
  public total = computed(() => this.subtotal() + this.tax());
}
```

---

## 2. Dynamic Dependency Tracking

Angular Signals track dependencies **dynamically during execution**. If your computed signal contains conditional branches (`if/else`), only the signals read in the *currently active branch* are registered as dependencies:

```typescript
export class DynamicDependencyExample {
  public isMember = signal(false);
  public standardDiscount = signal(0.05);
  public vipDiscount = signal(0.25);

  public effectiveDiscount = computed(() => {
    if (this.isMember()) {
      // In this branch, ONLY 'isMember' and 'vipDiscount' are tracked!
      // Mutations to 'standardDiscount' will NOT trigger re-computation!
      return this.vipDiscount();
    } else {
      return this.standardDiscount();
    }
  });
}
```

---

## 3. Reactive Effects (`effect()`)

An **`effect()`** is an operation that runs whenever one or more of its tracked signal dependencies change. 

Unlike `computed()` (which calculates pure values), `effect()` is designed exclusively for **Side Effects**:
- Synchronizing state with `localStorage` or `sessionStorage`.
- Logging analytics or telemetry events.
- Interfacing with third-party non-Angular libraries (D3, Chart.js, Leaflet).
- Performing direct canvas or imperative DOM operations.

```typescript
import { Component, signal, effect, inject, PLATFORM_ID } from "@angular/core";
import { isPlatformBrowser } from "@angular/common";

@Component({
  selector: "app-theme-manager",
  standalone: true,
  template: `<button (click)="toggle()">Toggle Theme</button>`,
})
export class ThemeManagerComponent {
  private platformId = inject(PLATFORM_ID);
  public theme = signal<"light" | "dark">("dark");

  constructor() {
    // Register effect within the constructor (Injection Context)
    effect(() => {
      const currentTheme = this.theme();

      // Guard browser APIs for SSR compatibility:
      if (isPlatformBrowser(this.platformId)) {
        console.log(`[Effect]: Theme changed to ${currentTheme}`);
        localStorage.setItem("app_theme", currentTheme);
        document.documentElement.setAttribute("data-theme", currentTheme);
      }
    });
  }

  public toggle(): void {
    this.theme.update((t) => (t === "dark" ? "light" : "dark"));
  }
}
```

---

## 4. Effect Cleanups (`onCleanup`)

If an effect sets up a subscription, timer, or DOM event listener, it must register a **cleanup function** via the `onCleanup` parameter. 

The cleanup function executes:
1. Before the effect re-runs (when dependencies change).
2. When the containing component or service is destroyed.

```typescript
import { Component, signal, effect } from "@angular/core";

@Component({
  selector: "app-telemetry-poller",
  standalone: true,
  template: `<p>Status: Monitoring Endpoint</p>`,
})
export class TelemetryPollerComponent {
  public endpointUrl = signal("https://api.example.com/v1/telemetry");

  constructor() {
    effect((onCleanup) => {
      const url = this.endpointUrl();
      console.log(`Starting telemetry polling for: ${url}`);

      const timerId = setInterval(() => {
        console.log(`Pinging ${url}...`);
      }, 5000);

      // Cleanup registration:
      onCleanup(() => {
        console.log(`Stopping telemetry polling for: ${url}`);
        clearInterval(timerId);
      });
    });
  }
}
```

---

## 5. The Injection Context & `Injector`

Effects require an active **Injection Context** to register their automatic destruction lifecycle with the host component. 

If you need to create an effect outside a constructor (e.g. inside a method or callback), manually pass the `Injector`:

```typescript
import { Component, inject, Injector, effect, signal } from "@angular/core";

@Component({
  selector: "app-dynamic-effect",
  standalone: true,
  template: `<button (click)="startMonitoring()">Start Monitoring</button>`,
})
export class DynamicEffectComponent {
  private injector = inject(Injector);
  public status = signal("idle");

  public startMonitoring(): void {
    // Create effect outside constructor using explicit injector:
    const effectRef = effect(
      () => {
        console.log("Current status:", this.status());
      },
      { injector: this.injector }
    );

    // Manual destruction if needed:
    // effectRef.destroy();
  }
}
```

---

## 6. The `allowSignalWrites` Option (Anti-Pattern Warning)

By default, Angular throws an error if you attempt to mutate a writable signal inside an `effect()`:
> `Error: NG0600: Writing to signals is not allowed in a computed or an effect by default.`

Mutating signals inside effects creates cascading updates, infinite loops, and race conditions. If you need derived state, **always use `computed()` instead of writing to a signal inside an `effect()`**.

In rare scenarios (e.g. synchronizing with external library callbacks), you can opt-in:

```typescript
effect(
  () => {
    // ...
  },
  { allowSignalWrites: true } // Use with extreme caution!
);
```

---

## Troubleshooting & Best Practices

1. **Never use `effect()` to update other signals**
   ```typescript
   // ❌ BAD ANTI-PATTERN:
   effect(() => {
     this.total.set(this.price() * this.qty()); // Triggers NG0600 error!
   });

   // ✅ CORRECT: Use computed()
   public total = computed(() => this.price() * this.qty());
   ```

2. **Always guard browser-only globals in SSR effects**
   Because effects execute during SSR pre-rendering on the Node.js server, checking `isPlatformBrowser(platformId)` prevents `ReferenceError: localStorage is not defined`.
