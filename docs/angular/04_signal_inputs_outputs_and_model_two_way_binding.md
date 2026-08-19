# Module 04: Signal Inputs, Signal Outputs & `model()` Two-Way Binding

**Track:** Angular — Signals Platform & Ivy Architecture
**Category:** Component Communication, Signal Inputs & Reactive Queries

---

## 1. The Modern Signal Component API (Angular 17.1+)

Historically, Angular components communicated via decorator-based properties: `@Input()`, `@Output() = new EventEmitter()`, and `@ViewChild()`.

In modern Angular:

- **`input()` / `input.required()`** replaces `@Input()` with reactive read-only signals.
- **`output()`** replaces `@Output() = new EventEmitter()` with a lightweight, type-safe event dispatcher.
- **`model()`** replaces cumbersome two-way binding boilerplate (`[value]` + `(valueChange)`) with a single writable signal.
- **`viewChild()` / `contentChild()`** replace `@ViewChild` with reactive signals that update automatically when DOM queries resolve.

| Legacy Decorator API | Modern Signal-Based API | Return Type |
| :--- | :--- | :--- |
| `@Input() title: string = ""` | `title = input<string>("")` | `InputSignal<string>` |
| `@Input({ required: true }) id!: string` | `id = input.required<string>()` | `InputSignal<string>` |
| `@Output() change = new EventEmitter()` | `change = output<string>()` | `OutputEmitterRef<string>` |
| `[value]="v" (valueChange)="v = $event"` | `value = model<string>("")` | `ModelSignal<string>` |
| `@ViewChild('canvas') canvas!: ElementRef` | `canvas = viewChild<ElementRef>('canvas')` | `Signal<ElementRef \| undefined>` |

---

## 2. Signal Inputs (`input()` & `input.required()`)

A Signal Input is a **read-only signal**. Whenever the parent component passes a new value, the signal updates automatically and can be consumed directly inside `computed()` or template expressions.

```typescript
import { Component, input, computed, booleanAttribute, numberAttribute } from "@angular/core";

@Component({
  selector: "app-user-profile-badge",
  standalone: true,
  template: `
    <div class="badge" [class.badge--vip]="isVip()" [class.badge--disabled]="disabled()">
      <span class="name">{{ displayName() }}</span>
      <span class="level">Level: {{ level() }}</span>
    </div>
  `,
})
export class UserProfileBadgeComponent {
  // 1. Mandatory Signal Input:
  public userId = input.required<string>();

  // 2. Optional Signal Input with default:
  public username = input<string>("Anonymous");

  // 3. Input with Built-In Type Transforms (e.g. string to number/boolean):
  public level = input(1, { transform: numberAttribute });
  public disabled = input(false, { transform: booleanAttribute });
  public isVip = input(false, { transform: booleanAttribute });

  // 4. Derived state calculated cleanly via computed():
  public displayName = computed(() => {
    return this.isVip() ? `👑 ${this.username().toUpperCase()}` : this.username();
  });
}
```

### Consuming the Component in Templates

```html
<!-- Parent Template: Notice standard property binding [input] still applies! -->
<app-user-profile-badge
  [userId]="selectedUserId()"
  [username]="selectedUserName()"
  level="42"       <!-- Automatically transformed to number 42 via numberAttribute! -->
  isVip            <!-- Boolean attribute coercion: isVip becomes true! -->
/>
```

---

## 3. Signal Outputs (`output()`)

Signal Outputs emit events to parent components without the runtime overhead of RxJS `EventEmitter`:

```typescript
import { Component, output } from "@angular/core";

export interface DeleteEvent {
  itemId: string;
  confirmedAt: Date;
}

@Component({
  selector: "app-delete-button",
  standalone: true,
  template: `
    <button (click)="handleDelete()" class="btn-danger">
      Delete Item
    </button>
  `,
})
export class DeleteButtonComponent {
  public itemId = input.required<string>();

  // Declare Signal Output:
  public deleted = output<DeleteEvent>();

  public handleDelete(): void {
    this.deleted.emit({
      itemId: this.itemId(),
      confirmedAt: new Date(),
    });
  }
}
```

---

## 4. Two-Way Model Binding with `model()`

In legacy Angular, creating a two-way bindable component required declaring an `@Input() value` and a paired `@Output() valueChange`.

**`model()`** creates a **Writable Signal** that can be bound two-way using the standard "banana-in-a-box" syntax (`[(prop)]="val"`):

```typescript
// src/app/shared/components/rating.component.ts
import { Component, model } from "@angular/core";

@Component({
  selector: "app-rating",
  standalone: true,
  template: `
    <div class="star-rating">
      @for (star of [1, 2, 3, 4, 5]; track star) {
        <button
          type="button"
          (click)="setRating(star)"
          [class.active]="rating() >= star"
        >
          ★
        </button>
      }
    </div>
  `,
  styles: [`
    .star-rating button { font-size: 1.5rem; background: none; border: none; cursor: pointer; color: #475569; }
    .star-rating button.active { color: #eab308; }
  `],
})
export class RatingComponent {
  // Two-way Model Signal:
  public rating = model<number>(1);

  public setRating(val: number): void {
    this.rating.set(val); // Updates local signal and notifies parent two-way binding!
  }
}
```

### Consuming Two-Way Binding in Parent Component

```typescript
// Parent Component:
export class ProductReviewComponent {
  public userRating = signal<number>(4);
}
```

```html
<!-- Parent Template: Two-way synchronization with [(rating)] -->
<app-rating [(rating)]="userRating" />
<p>Selected Rating: {{ userRating() }} Stars</p>
```

---

## 5. Signal Queries (`viewChild` & `contentChild`)

Signal queries replace `@ViewChild` and `@ContentChild` with reactive signals that automatically update if child elements appear conditionally (e.g. inside `@if`):

```typescript
import { Component, viewChild, ElementRef, effect } from "@angular/core";

@Component({
  selector: "app-auto-focus-input",
  standalone: true,
  template: `
    <input #searchBox type="text" placeholder="Type to search..." />
  `,
})
export class AutoFocusInputComponent {
  // Reactive viewChild Signal:
  public searchInput = viewChild.required<ElementRef<HTMLInputElement>>("searchBox");

  constructor() {
    effect(() => {
      // Access the real DOM element reactively once mounted:
      const el = this.searchInput().nativeElement;
      el.focus();
    });
  }
}
```

---

## Troubleshooting & Best Practices

1. **Do NOT attempt to mutate an `input()` signal**
   Input signals are strictly read-only (`InputSignal<T>`). Calling `this.myInput.set(val)` will throw a compile error. If you need a property that can be mutated both by the child and the parent, use `model()`.

2. **Always use `input.required()` for mandatory parameters**
   `input.required()` guarantees that TypeScript catches missing template bindings at compile time.
