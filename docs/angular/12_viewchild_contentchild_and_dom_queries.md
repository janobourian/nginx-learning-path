# Module 12: DOM Queries, Signal Queries & Platform-Agnostic `Renderer2`

**Track:** Angular — Signals Platform & Ivy Architecture
**Category:** DOM Queries, View Trees & Native Element Manipulation

---

## 1. View DOM vs Projected Content DOM

In Angular component architecture, there are two distinct DOM query spaces:

1. **View DOM (`viewChild` / `viewChildren`)**: Elements and components declared **inside the component's own HTML template**.
2. **Projected Content DOM (`contentChild` / `contentChildren`)**: Elements and components passed into the component from a parent via `<ng-content>` content projection.

```text
Component Query Scope:
<app-card> ◄── Parent passes projected content
  <span class="user-badge">Alice</span> ◄── Targeted by @ContentChild / contentChild
</app-card>

CardComponent Template:
<div class="card-container">
  <input #internalInput />  ◄── Targeted by @ViewChild / viewChild
  <ng-content />
</div>
```

---

## 2. Signal Queries (`viewChild` & `viewChildren`)

In modern Angular (v17.2+), **Signal Queries** replace legacy decorators:

| Feature | Legacy `@ViewChild('id')` | Modern `viewChild('id')` |
| :--- | :--- | :--- |
| **Return Type** | Plain property (initially `undefined` until `ngAfterViewInit`) | **Reactive `Signal<T \| undefined>`** |
| **Lifecycle Timing** | Only accessible after `ngAfterViewInit` | Accessible reactively inside `effect()` and `computed()` |
| **Dynamic Elements** | Required manual `ngOnChanges` checks | **Automatically updates when `@if` branches toggle!** |

```typescript
import { Component, viewChild, viewChildren, ElementRef, effect } from "@angular/core";

@Component({
  selector: "app-canvas-editor",
  standalone: true,
  template: `
    <canvas #mainCanvas width="800" height="600"></canvas>
    <div class="color-palette">
      @for (color of colors; track color) {
        <button #colorBtn [style.background]="color">{{ color }}</button>
      }
    </div>
  `,
})
export class CanvasEditorComponent {
  public colors = ["#ef4444", "#3b82f6", "#10b981", "#f59e0b"];

  // 1. Single View Query Signal:
  public canvasRef = viewChild.required<ElementRef<HTMLCanvasElement>>("mainCanvas");

  // 2. Multi-Element Query Signal:
  public colorButtons = viewChildren<ElementRef<HTMLButtonElement>>("colorBtn");

  constructor() {
    effect(() => {
      // Access canvas context reactively:
      const canvas = this.canvasRef().nativeElement;
      const ctx = canvas.getContext("2d");
      if (ctx) {
        ctx.fillStyle = "#1e293b";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
      }
    });

    effect(() => {
      console.log(`Rendered ${this.colorButtons().length} color palette buttons`);
    });
  }
}
```

---

## 3. Querying Specific Tokens with `{ read: ... }`

When an element has multiple directives, components, or references attached to it, specify `{ read: Token }` to extract the desired handle:

```typescript
import {
  Component,
  viewChild,
  ElementRef,
  TemplateRef,
  ViewContainerRef,
} from "@angular/core";

@Component({
  selector: "app-query-demo",
  standalone: true,
  template: `
    <div #containerBox class="box">Container</div>
    <ng-template #dynamicTemplate>Dynamic Markup</ng-template>
  `,
})
export class QueryDemoComponent {
  // 1. Read raw DOM ElementRef:
  public boxElement = viewChild("containerBox", { read: ElementRef });

  // 2. Read ViewContainerRef (for dynamic component/template instantiation):
  public boxContainer = viewChild("containerBox", { read: ViewContainerRef });

  // 3. Read TemplateRef:
  public customTemplate = viewChild("dynamicTemplate", { read: TemplateRef });
}
```

---

## 4. Projected Content Queries (`contentChild` & `contentChildren`)

Use `contentChild` to interact with components projected into `<ng-content>`:

```typescript
// src/app/shared/components/accordion-panel.component.ts
import { Component, input } from "@angular/core";

@Component({
  selector: "app-accordion-panel",
  standalone: true,
  template: `
    <div class="panel">
      <h4>{{ title() }}</h4>
      <ng-content />
    </div>
  `,
})
export class AccordionPanelComponent {
  public title = input.required<string>();
  public isExpanded = false;
}
```

```typescript
// src/app/shared/components/accordion.component.ts
import { Component, contentChildren, effect } from "@angular/core";
import { AccordionPanelComponent } from "./accordion-panel.component";

@Component({
  selector: "app-accordion",
  standalone: true,
  template: `
    <div class="accordion-group">
      <ng-content />
    </div>
  `,
})
export class AccordionComponent {
  // Query all child AccordionPanelComponent instances projected from parent:
  public panels = contentChildren(AccordionPanelComponent);

  constructor() {
    effect(() => {
      console.log(`Accordion contains ${this.panels().length} projected panels`);
    });
  }
}
```

---

## 5. Platform-Agnostic DOM Manipulation with `Renderer2`

Direct DOM manipulation (`element.style.color = 'red'`, `document.body.appendChild`) will crash during Server-Side Rendering (SSR) and web workers.

Always use **`Renderer2`** for platform-agnostic DOM operations:

```typescript
import { Directive, ElementRef, inject, Renderer2, OnInit } from "@angular/core";

@Directive({
  selector: "[appHighlight]",
  standalone: true,
})
export class HighlightDirective implements OnInit {
  private el = inject(ElementRef);
  private renderer = inject(Renderer2);

  ngOnInit(): void {
    // Safe across Browser, Node.js SSR, and Web Workers!
    this.renderer.setStyle(this.el.nativeElement, "backgroundColor", "#fef08a");
    this.renderer.setStyle(this.el.nativeElement, "padding", "4px 8px");
    this.renderer.setStyle(this.el.nativeElement, "borderRadius", "4px");
  }
}
```

---

## Troubleshooting & Best Practices

1. **`nativeElement` Direct Access Security**
   Accessing `elementRef.nativeElement` directly introduces security vulnerabilities (XSS) and SSR crashes. Only read properties from `nativeElement` when strictly necessary, and use `Renderer2` for all mutations.

2. **Signal Queries inside `@if` blocks**
   If an element is inside an `@if (isOpen())` block, `viewChild()` evaluates to `undefined` when closed, and automatically updates to the `ElementRef` the instant `isOpen()` becomes `true`!
