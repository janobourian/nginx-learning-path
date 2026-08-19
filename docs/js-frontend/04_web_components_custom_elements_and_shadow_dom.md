# Module 04: Web Components — Custom Elements, Shadow DOM & Constructable Stylesheets

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Component Architecture, Encapsulation & Web Standards

---

## 1. The Web Components Standard Suite

**Web Components** are a set of W3C standard browser APIs that allow you to create reusable, fully encapsulated UI components with native browser support without relying on any framework (React, Vue, Angular):

```text
┌─────────────────────────────────────────────────────────────┐
│                 The 3 Web Component Pillars                 │
├────────────────────┬────────────────────────────────────────┤
│ **1. Custom**      │ Define new HTML tags                   │
│    **Elements**    │ (`<enterprise-card>`, `<video-player>`)│
│                    │ with custom lifecycle callbacks.       │
├────────────────────┼────────────────────────────────────────┤
│ **2. Shadow DOM**  │ Complete DOM and CSS style             │
│                    │ encapsulation (Styles inside cannot    │
│                    │ leak out, global styles cannot bleed in│
├────────────────────┼────────────────────────────────────────┤
│ **3. HTML**        │ Reusable DOM fragments with named      │
│    **Templates &** │ projection slots (`<slot name="...">`).│
│    **Slots**       │                                        │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. The Custom Element Lifecycle Callbacks

```javascript
class EnterpriseWidget extends HTMLElement {
  // 1. Declare which HTML attributes trigger attributeChangedCallback:
  static get observedAttributes() {
    return ['status', 'theme', 'badge-count'];
  }

  constructor() {
    super();
    // 2. Attach Shadow Root (Open mode allows JS inspection):
    this.attachShadow({ mode: 'open' });
  }

  // 3. Invoked when element is mounted into live document DOM:
  connectedCallback() {
    console.log('[CustomElement]: Mounted to document');
    this.render();
  }

  // 4. Invoked when element is removed from DOM:
  disconnectedCallback() {
    console.log('[CustomElement]: Unmounted from document. Cleaning up listeners...');
  }

  // 5. Invoked when element is moved to a new document (e.g. iframe):
  adoptedCallback() {
    console.log('[CustomElement]: Adopted into new document');
  }

  // 6. Invoked when an observed attribute changes:
  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue !== newValue) {
      console.log(`[CustomElement]: Attribute '${name}' changed from '${oldValue}' to '${newValue}'`);
      this.render();
    }
  }

  render() {
    // Render Shadow DOM markup
  }
}

// Register custom HTML tag (Name MUST contain a hyphen!):
customElements.define('enterprise-widget', EnterpriseWidget);
```

---

## 3. Style Encapsulation & Constructable Stylesheets

In standard web apps, styling `<button>` in one component can accidentally break buttons across the entire website.

With **Shadow DOM**, styles are **100% scoped**. Using **Constructable Stylesheets (`CSSStyleSheet`)**, multiple component instances share the exact same compiled CSS rule in memory:

```javascript
// Compile CSS once in memory:
const componentSheet = new CSSStyleSheet();
componentSheet.replaceSync(`
  :host {
    display: inline-block;
    font-family: system-ui, sans-serif;
  }
  :host([theme="dark"]) {
    --card-bg: #0f172a;
    --text-color: #f8fafc;
  }
  .card-container {
    background: var(--card-bg, #ffffff);
    color: var(--text-color, #1e293b);
    border-radius: 12px;
    padding: 20px;
    box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  }
  ::slotted(h2) {
    margin: 0 0 12px 0;
    color: #4f46e5;
  }
`);

export class EncapsulatedCard extends HTMLElement {
  constructor() {
    super();
    const shadow = this.attachShadow({ mode: 'open' });
    // Adopt shared stylesheet:
    shadow.adoptedStyleSheets = [componentSheet];

    shadow.innerHTML = `
      <div class="card-container">
        <slot name="title"></slot>
        <slot name="content"></slot>
        <slot></slot> <!-- Default catch-all slot -->
      </div>
    `;
  }
}

customElements.define('encapsulated-card', EncapsulatedCard);
```

```html
<!-- Consuming in HTML: -->
<encapsulated-card theme="dark">
  <h2 slot="title">Enterprise Security Shield</h2>
  <p slot="content">Real-time threat monitoring active across all Kubernetes nodes.</p>
</encapsulated-card>
```

---

## 4. Form-Associated Custom Elements (`ElementInternals`)

Historically, custom elements could not participate in HTML `<form>` submissions or native form validation.

Modern browsers provide **`ElementInternals` (`this.attachInternals()`)**:

```javascript
// src/components/custom_rating_input.js
export class CustomRatingInput extends HTMLElement {
  static formAssociated = true; // ◄── Declares element can participate in forms!

  constructor() {
    super();
    this.internals = this.attachInternals();
    this.attachShadow({ mode: 'open' });
    this._value = '5';
  }

  connectedCallback() {
    this.shadowRoot.innerHTML = `
      <div class="rating-box">
        <button type="button" data-val="1">★</button>
        <button type="button" data-val="2">★</button>
        <button type="button" data-val="3">★</button>
        <button type="button" data-val="4">★</button>
        <button type="button" data-val="5">★</button>
      </div>
    `;

    this.shadowRoot.addEventListener('click', (e) => {
      const btn = e.target.closest('button');
      if (btn) {
        this.value = btn.dataset.val;
      }
    });

    this._updateFormValue();
  }

  get value() {
    return this._value;
  }

  set value(newVal) {
    this._value = newVal;
    this._updateFormValue();
  }

  _updateFormValue() {
    // 1. Submit value automatically with parent HTML <form>:
    this.internals.setFormValue(this._value);

    // 2. Native Form Validation:
    if (Number(this._value) < 1) {
      this.internals.setValidity({ customError: true }, 'Rating must be at least 1 star');
    } else {
      this.internals.setValidity({}); // Valid
    }
  }
}

customElements.define('custom-rating-input', CustomRatingInput);
```

```html
<!-- Works seamlessly with standard HTML forms: -->
<form action="/submit-feedback" method="POST">
  <label>Your Score:</label>
  <custom-rating-input name="user_score"></custom-rating-input>
  <button type="submit">Submit Feedback</button>
</form>
```

---

## Troubleshooting & Best Practices

1. **Custom Element Names MUST Contain a Hyphen (`-`)**
   HTML tag names like `<card>` are invalid and will throw a `DOMException: Registration failed`. Always use at least one hyphen (e.g. `<app-card>`, `<acme-button>`) to distinguish custom elements from future native HTML tags.

2. **Never Manipulate Children in the `constructor()`**
   In the `constructor()`, child DOM nodes and attributes have not yet been parsed. Perform DOM updates, event listeners, and attribute inspections inside **`connectedCallback()`**.
