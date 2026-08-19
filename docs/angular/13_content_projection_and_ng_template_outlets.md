# Module 13: Content Projection & Dynamic Templates (`ngTemplateOutlet`)

**Track:** Angular — Signals Platform & Ivy Architecture
**Category:** Component Composition, Transclusion & Headless UI

---

## 1. What Is Content Projection?

**Content Projection** (also known as transclusion or slot-based rendering) allows a parent component to inject custom HTML, directives, or other components into designated placeholder slots inside a child component's template.

---

## 2. Multi-Slot Content Projection with Selectors

Child components can declare multiple distinct insertion slots using CSS selectors in the `select` attribute of `<ng-content>`:

```typescript
// src/app/shared/components/modal.component.ts
import { Component, input, output } from "@angular/core";

@Component({
  selector: "app-modal-dialog",
  standalone: true,
  template: `
    <div class="modal-backdrop" (click)="close.emit()">
      <div class="modal-card" (click)="$event.stopPropagation()">

        <!-- Slot 1: Modal Header (Matches elements with [modal-header] attribute) -->
        <header class="modal-header">
          <ng-content select="[modal-header]">
            <!-- Angular 18+ Default Fallback Content if slot is empty! -->
            <h3>Default Dialog Title</h3>
          </ng-content>
        </header>

        <!-- Slot 2: Main Body (Catch-all for unselected elements) -->
        <div class="modal-body">
          <ng-content />
        </div>

        <!-- Slot 3: Actions Footer (Matches elements with [modal-actions] attribute) -->
        <footer class="modal-footer">
          <ng-content select="[modal-actions]">
            <button (click)="close.emit()">Close</button>
          </ng-content>
        </footer>

      </div>
    </div>
  `,
})
export class ModalDialogComponent {
  public close = output<void>();
}
```

### Consuming the Multi-Slot Component

```html
<app-modal-dialog (close)="isModalOpen.set(false)">
  <!-- Projected into Slot 1: -->
  <h2 modal-header class="text-xl font-bold text-indigo-400">
    Confirm Data Deletion
  </h2>

  <!-- Projected into Slot 2 (Catch-All Body): -->
  <p>Are you sure you want to permanently delete record #42?</p>

  <!-- Projected into Slot 3: -->
  <div modal-actions class="flex gap-2">
    <button (click)="isModalOpen.set(false)">Cancel</button>
    <button (click)="confirmDelete()" class="btn-danger">Delete</button>
  </div>
</app-modal-dialog>
```

---

## 3. Dynamic Templates with `ngTemplateOutlet`

While `<ng-content>` projects static content at compile time, **`ngTemplateOutlet`** enables **dynamic, programmatic template rendering with custom contextual data** (essential for data tables, virtual lists, and headless UI libraries).

```text
ngTemplateOutlet Pipeline:
[Parent Template: <ng-template let-user="user">]
                        │
                        ▼ (Pass TemplateRef as Input Prop)
[Child DataTableComponent]
        │
        ▼ (Renders template for each row with { $implicit: rowData })
[DOM Output: Custom row markup rendered for 1,000 rows dynamically!]
```

---

## 4. Production Master Example: Headless Typed Data Table

Let's build a highly customizable, reusable Data Table component where consumers can provide custom template templates for table cells:

```typescript
// src/app/shared/components/data-table/data-table.component.ts
import { Component, input, TemplateRef } from "@angular/core";
import { CommonModule } from "@angular/common";

export interface TableColumn<T> {
  key: keyof T & string;
  header: string;
  // Optional custom cell template passed by parent:
  cellTemplate?: TemplateRef<{ $implicit: T[keyof T]; row: T; index: number }>;
}

@Component({
  selector: "app-data-table",
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="table-responsive">
      <table class="data-table">
        <thead>
          <tr>
            @for (col of columns(); track col.key) {
              <th>{{ col.header }}</th>
            }
          </tr>
        </thead>
        <tbody>
          @for (row of data(); track $index; let rowIndex = $index) {
            <tr>
              @for (col of columns(); track col.key) {
                <td>
                  <!-- If a custom cell template was provided, render it with context! -->
                  @if (col.cellTemplate) {
                    <ng-container
                      *ngTemplateOutlet="
                        col.cellTemplate;
                        context: { $implicit: row[col.key], row: row, index: rowIndex }
                      "
                    />
                  } @else {
                    <!-- Default fallback: render raw value -->
                    {{ row[col.key] }}
                  }
                </td>
              }
            </tr>
          }
        </tbody>
      </table>
    </div>
  `,
  styleUrls: ["./data-table.component.css"],
})
export class DataTableComponent<T> {
  public data = input.required<T[]>();
  public columns = input.required<TableColumn<T>[]>();
}
```

---

## 5. Consuming the Data Table with Custom Cell Templates

```typescript
// src/app/features/users/user-list.component.ts
import { Component, viewChild, TemplateRef, signal } from "@angular/core";
import { DataTableComponent, type TableColumn } from "@/shared/components/data-table/data-table.component";

interface UserRecord {
  id: string;
  name: string;
  email: string;
  status: "active" | "suspended";
}

@Component({
  selector: "app-user-list",
  standalone: true,
  imports: [DataTableComponent],
  template: `
    <h2>Enterprise User Directory</h2>

    <!-- Custom Cell Template for Status column: -->
    <ng-template #statusCell let-status let-user="row">
      <span
        class="badge"
        [class.badge--green]="status === 'active'"
        [class.badge--red]="status === 'suspended'"
      >
        {{ status | uppercase }} (ID: {{ user.id }})
      </span>
    </ng-template>

    <app-data-table [data]="users()" [columns]="tableColumns" />
  `,
})
export class UserListComponent {
  private statusTemplate = viewChild.required<TemplateRef<any>>("statusCell");

  public users = signal<UserRecord[]>([
    { id: "u_1", name: "Alice Chen", email: "alice@acme.com", status: "active" },
    { id: "u_2", name: "Bob Smith", email: "bob@acme.com", status: "suspended" },
  ]);

  public get tableColumns(): TableColumn<UserRecord>[] {
    return [
      { key: "name", header: "Full Name" },
      { key: "email", header: "Email Address" },
      { key: "status", header: "Account Status", cellTemplate: this.statusTemplate() },
    ];
  }
}
```

---

## Troubleshooting & Best Practices

1. **The `$implicit` Context Property**
   In `context: { $implicit: value }`, `$implicit` maps to the default variable assigned when the consumer writes `<ng-template let-val>`. Named properties require explicit binding: `<ng-template let-customName="propertyName">`.

2. **`<ng-content>` is NOT Conditionally Created**
   `<ng-content>` **always** instantiates its projected components, even if wrapped in `@if (false)`. If you need conditional instantiation to avoid computing heavy DOM nodes when hidden, use `<ng-template>` and `*ngTemplateOutlet`.
