# Module 01: Standalone Components, Built-in Control Flow & `@defer`

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Component Architecture, Template Control Flow & Deferrable Views

---

## 1. The Standalone Architecture Revolution

In legacy Angular (v2–v14), every component had to be declared inside an `@NgModule`. This created tight coupling, confusing import loops, and forced entire modules to be bundled together.

In modern Angular (v17+):
- Components declare `standalone: true` and explicitly list only the direct dependencies they consume in `imports: [...]`.
- Standalone components can be imported directly into other standalone components, routes, or tests.
- **NgModules are completely optional and deprecated for new projects.**

```typescript
import { Component } from "@angular/core";
import { UserAvatarComponent } from "./user-avatar.component";
import { FormatDatePipe } from "./format-date.pipe";

@Component({
  selector: "app-user-card",
  standalone: true,
  imports: [UserAvatarComponent, FormatDatePipe], // Direct explicit dependencies
  template: `
    <div class="user-card">
      <app-user-avatar [url]="avatarUrl" />
      <h3>{{ name }}</h3>
      <p>Member since: {{ joinDate | formatDate }}</p>
    </div>
  `,
})
export class UserCardComponent {
  public avatarUrl = "https://example.com/avatar.png";
  public name = "Alice Chen";
  public joinDate = new Date();
}
```

---

## 2. Built-in Control Flow Syntax (`@if`, `@for`, `@switch`)

Angular 17 introduced a native, ergonomic control flow syntax built directly into the Angular template compiler. It replaces legacy micro-syntax directives (`*ngIf`, `*ngFor`, `*ngSwitch`) with zero required imports and higher runtime performance.

### 1. Conditional Rendering (`@if`, `@else if`, `@else`)

```html
@if (user(); as u) {
  <div class="profile">
    <h2>Welcome, {{ u.name }}!</h2>
    @if (u.role === 'admin') {
      <span class="badge-admin">System Administrator</span>
    } @else if (u.role === 'editor') {
      <span class="badge-editor">Editor</span>
    } @else {
      <span class="badge-member">Standard Member</span>
    }
  </div>
} @else {
  <div class="login-prompt">
    <p>Please log in to continue.</p>
  </div>
}
```

### 2. Loops & Collections (`@for` with Mandatory `track`)

In the new `@for` block, **`track` is mandatory**. Tracking unique identifiers (like `item.id`) enables Angular's Ivy compiler to execute optimal DOM node recycling without re-rendering the entire list.

The `@empty` block renders automatically when the array is empty:

```html
<ul class="task-list">
  @for (task of tasks(); track task.id; let idx = $index; let total = $count; let isFirst = $first) {
    <li class="task-item" [class.highlight]="isFirst">
      <span>#{{ idx + 1 }} of {{ total }}: {{ task.title }}</span>
      <span class="status">{{ task.completed ? '✅ Done' : '⏳ Pending' }}</span>
    </li>
  } @empty {
    <li class="empty-state">
      <p>No tasks found. Create your first task above!</p>
    </li>
  }
</ul>
```

### Contextual Variables in `@for`:
- `$index`: 0-indexed position of the item.
- `$count`: Total number of items in the iterable.
- `$first`: Boolean, true if first item.
- `$last`: Boolean, true if last item.
- `$even`: Boolean, true if even index.
- `$odd`: Boolean, true if odd index.

### 3. Switch Statements (`@switch`, `@case`, `@default`)

```html
@switch (notification().type) {
  @case ('success') {
    <div class="alert alert-success">Operation completed successfully!</div>
  }
  @case ('warning') {
    <div class="alert alert-warning">Please review your storage quota.</div>
  }
  @case ('error') {
    <div class="alert alert-danger">Critical system error occurred.</div>
  }
  @default {
    <div class="alert alert-info">General system notification.</div>
  }
}
```

---

## 3. Deferrable Views (`@defer`)

**Deferrable Views (`@defer`)** is one of modern Angular's most revolutionary features. It allows developers to **lazy-load and code-split any template section and its component dependencies automatically** with zero manual routing or dynamic `import()` code!

```
@defer Lifecycle Blocks:
1. @placeholder ──► Lightweight markup shown before defer condition triggers
2. @loading     ──► Skeletons shown while component JavaScript chunk downloads
3. @defer       ──► Real component rendered once downloaded & condition met!
4. @error       ──► Fallback UI shown if network request fails
```

### Defer Triggers:

| Trigger | Meaning | Example |
| :--- | :--- | :--- |
| **`on viewport`** | Lazy loads when element enters the browser viewport | `@defer (on viewport)` |
| **`on hover`** | Lazy loads when user hovers over placeholder | `@defer (on hover)` |
| **`on interaction`** | Lazy loads when user clicks or types in placeholder | `@defer (on interaction)` |
| **`on idle`** | Loads during browser idle time (`requestIdleCallback`) | `@defer (on idle)` |
| **`when condition`** | Loads when a custom signal evaluates to `true` | `@defer (when isChartVisible())` |
| **`prefetch`** | Pre-fetches chunk in background before user triggers it | `@defer (on interaction; prefetch on idle)` |

### Production Defer Example (Heavy Data Chart):

```html
<!-- src/app/features/analytics/analytics.component.html -->
<section class="analytics-container">
  <h2>Annual Revenue Telemetry</h2>

  <!-- The HeavyChartComponent and all its D3/Canvas libraries are NOT in the initial bundle!
       They are downloaded ONLY when the user scrolls down and the placeholder enters the viewport! -->
  @defer (on viewport; prefetch on idle) {
    <app-heavy-chart [data]="revenueData()" />
  } @placeholder (minimum 500ms) {
    <div class="chart-placeholder bg-slate-900 border border-slate-800 p-8 rounded text-center">
      <p class="text-slate-400">Scroll to view interactive revenue graph</p>
    </div>
  } @loading (after 100ms; minimum 500ms) {
    <!-- minimum 500ms prevents jarring visual flashing on fast connections! -->
    <div class="chart-skeleton animate-pulse bg-slate-800 h-64 rounded" />
  } @error {
    <div class="alert-error">
      <p>Failed to download telemetry visualization engine.</p>
    </div>
  }
</section>
```

---

## Troubleshooting & Best Practices

1. **`track` by unique identity, not index**
   In `@for (item of items; track $index)`, tracking by `$index` prevents Angular from reusing DOM nodes when items are inserted, deleted, or sorted. Always track unique IDs (`track item.id`).

2. **Preventing `@loading` Flicker with `minimum` and `after`**
   If a network request finishes in 20ms, showing a loading skeleton for 20ms causes a jarring flicker. Use `@loading (after 100ms; minimum 500ms)` so fast requests skip the skeleton entirely, and slow requests show a stable skeleton for at least 500ms.
