# Module 02: Event Propagation, Event Delegation & Passive Listeners

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Event System, Event Bubbling & Performance Optimization

---

## 1. The 3 Phases of DOM Event Propagation

When you click an HTML element, the event does not execute solely on that single node. The browser dispatches the event through **three distinct phases**:

```text
┌─────────────────────────────────────────────────────────────┐
│                 The 3 DOM Event Propagation Phases          │
│                                                             │
│  [Window]                                                   │
│     │ (1. Capturing Phase: Top ──► Down)                    │
│     ▼                                                       │
│  [Document]                                                 │
│     ▼                                                       │
│  [<body>]                                                   │
│     ▼                                                       │
│  [<div id="parent">]                                        │
│     ▼                                                       │
│  [<button id="target">] ◄── (2. Target Phase: Executes here)│
│     │                                                       │
│     ▼ (3. Bubbling Phase: Bottom ──► Up)                    │
│  [<div id="parent">]                                        │
│     ▼                                                       │
│  [<body>] ──► [Document] ──► [Window]                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Capturing vs Bubbling in `addEventListener`

By default, event listeners trigger during the **Bubbling Phase**:

```javascript
// Trigger during Capturing Phase (Top -> Down):
element.addEventListener('click', handler, { capture: true });

// Trigger during Bubbling Phase (Bottom -> Up - Default):
element.addEventListener('click', handler, { capture: false });
```

---

## 3. High-Performance Event Delegation

### The Problem: Memory Bloat with Thousands of Listeners

If you render a table with 5,000 rows and attach a `click` listener to every delete button, you allocate **5,000 listener closures in memory**. When rows are dynamically added or deleted, managing listener lifecycles causes memory leaks.

### The Solution: Event Delegation

Attach **a single listener on the parent container** and inspect `event.target.closest()` as events bubble upward:

```html
<table id="enterprise-table">
  <tbody>
    <tr data-id="101">
      <td>Alice Chen</td>
      <td><button class="action-btn delete" data-action="delete">Delete</button></td>
    </tr>
    <tr data-id="102">
      <td>Bob Smith</td>
      <td><button class="action-btn edit" data-action="edit">Edit</button></td>
    </tr>
  </tbody>
</table>
```

```javascript
// Exactly 1 listener for the ENTIRE table (Handles infinite dynamic rows!):
const table = document.querySelector('#enterprise-table');

table.addEventListener('click', (event) => {
  // Find the button clicked (or child icon inside button):
  const button = event.target.closest('button.action-btn');
  if (!button || !table.contains(button)) return;

  const row = button.closest('tr');
  const userId = row.dataset.id;
  const action = button.dataset.action;

  if (action === 'delete') {
    console.log(`Deleting user #${userId}`);
    row.remove();
  } else if (action === 'edit') {
    console.log(`Editing user #${userId}`);
  }
});
```

---

## 4. `target` vs `currentTarget`

```javascript
element.addEventListener('click', (event) => {
  // event.target: The innermost element the user physically clicked (e.g. <span> or <i> icon)
  console.log('Clicked Element:', event.target);

  // event.currentTarget: The element that this event listener is bound to (e.g. <button>)
  console.log('Bound Container:', event.currentTarget);
});
```

---

## 5. Controlling Event Flow

| Method | Behavior |
| :--- | :--- |
| **`event.preventDefault()`** | Cancels browser default action (e.g. stops form submit page reload or link navigation). |
| **`event.stopPropagation()`** | Prevents event from bubbling further up (or capturing down) the DOM tree. |
| **`event.stopImmediatePropagation()`** | Prevents event from bubbling AND **stops any other listeners registered on the same element** from firing! |

---

## 6. High-Performance Scrolling with Passive Listeners (`{ passive: true }`)

When handling `touchstart`, `touchmove`, or `wheel` scroll events, the browser must pause the main UI scrolling thread to check if your JavaScript code calls `event.preventDefault()`. This causes noticeable scrolling stutter on mobile devices.

Setting **`{ passive: true }`** promises the browser you will never call `preventDefault()`, allowing the browser to scroll the GPU compositor thread with **zero touch-latency**:

```javascript
window.addEventListener('touchmove', onTouchMove, { passive: true });
```

---

## 7. Automatic Cleanup with `AbortController` (No `removeEventListener` Needed!)

Instead of manually tracking `element.removeEventListener()`, pass an **`AbortSignal`** to automatically remove multiple listeners when a component unmounts:

```javascript
class DashboardComponent {
  constructor() {
    this.abortController = new AbortController();
  }

  mount() {
    const { signal } = this.abortController;

    // Register multiple listeners sharing the same abort signal:
    window.addEventListener('resize', this.onResize, { signal });
    window.addEventListener('keydown', this.onKeyDown, { signal });
    document.addEventListener('visibilitychange', this.onVisibility, { signal });
  }

  unmount() {
    // Automatically removes ALL registered event listeners in one command!
    this.abortController.abort();
  }
}
```

---

## Troubleshooting & Best Practices

1. **`this` vs Arrow Functions in Listeners**
   In arrow functions `(event) => { this }`, `this` retains lexical scope. If you need a reference to the bound element, access **`event.currentTarget`** rather than relying on `this`.

2. **Custom Events with `CustomEvent`**
   When building modular UI widgets, communicate upward by dispatching typed custom events with `element.dispatchEvent(new CustomEvent('metric-updated', { bubbles: true, detail: { cpu: 85 } }))`.
