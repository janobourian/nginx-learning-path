# Module 01: High-Performance DOM Manipulation, Traversal & Tree Mutations

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** DOM Architecture, Tree Traversals & Batch Mutations

---

## 1. The DOM Tree Architecture (`Node` vs `Element`)

The **Document Object Model (DOM)** is a tree structure representing an HTML document:

```
┌─────────────────────────────────────────────────────────────┐
│                 DOM Node Hierarchy Hierarchy                │
├────────────────────┬────────────────────────────────────────┤
│ **`EventTarget`**  │ Base interface for event handling      │
│                    │ (`addEventListener`, `dispatchEvent`). │
├────────────────────┼────────────────────────────────────────┤
│ **`Node`**         │ Base tree node: Elements, Text nodes,  │
│                    │ Comments, and DocumentFragments.       │
├────────────────────┼────────────────────────────────────────┤
│ **`Element`**      │ HTML/SVG elements with attributes and  │
│                    │ CSS classes (`div`, `button`, `svg`).  │
└────────────────────┴────────────────────────────────────────┘
```

```
DOM Tree Structure:
[Document]
   └── [Element: <html>]
         └── [Element: <body>]
               ├── [Element: <div id="card">]
               │     ├── [TextNode: "Hello "]
               │     └── [Element: <strong>] ──► [TextNode: "World"]
               └── [CommentNode: <!-- footer -->]
```

---

## 2. Modern DOM Traversal & Selection APIs

```javascript
// 1. Precise Query Selectors:
const submitBtn = document.querySelector('button[type="submit"].primary');
const allCards = document.querySelectorAll('.dashboard-card'); // Returns static NodeList

// 2. Traversal Upwards with closest():
// Finds the nearest ancestor matching the selector (or self):
const cardContainer = submitBtn.closest('.dashboard-card');

// 3. Predicate Checking with matches():
if (submitBtn.matches(':disabled')) {
  console.log('Button is currently disabled');
}

// 4. Ancestor Verification with contains():
if (cardContainer.contains(submitBtn)) {
  console.log('Submit button is inside card container');
}
```

---

## 3. High-Performance Batch DOM Mutations (`DocumentFragment`)

### The Performance Danger: Layout Thrashing in Loops

Inserting elements one-by-one inside a loop forces the browser to recalculate layouts (reflow) on every iteration:

```javascript
// ❌ HORRIBLE PERFORMANCE (1,000 DOM Reflow recalculations!):
const list = document.querySelector('#user-list');
for (const user of users) {
  const li = document.createElement('li');
  li.textContent = user.name;
  list.appendChild(li); // 💥 Forces reflow on every loop tick!
}
```

### The Optimized Solution: `DocumentFragment`

A **`DocumentFragment`** is an in-memory, lightweight DOM subtree that is not attached to the live document. Appending a fragment to the DOM triggers **exactly 1 single reflow**:

```javascript
// ✅ OPTIMIZED: Exactly 1 DOM Reflow for 1,000 items!
const list = document.querySelector('#user-list');
const fragment = document.createDocumentFragment();

for (const user of users) {
  const li = document.createElement('li');
  li.className = 'user-list-item';
  li.dataset.userId = user.id; // Custom data- attributes
  li.textContent = user.name;
  fragment.appendChild(li); // Appends in memory (0 live DOM reflows!)
}

list.appendChild(fragment); // ◄── Single atomic paint update!
```

---

## 4. Templating with `<template>` & `cloneNode()`

HTML `<template>` tags contain inert HTML markup that is parsed by the browser at page load but not rendered until cloned via JavaScript:

```html
<!-- HTML Template definition: -->
<template id="telemetry-card-template">
  <div class="telemetry-card">
    <h3 class="node-title"></h3>
    <span class="cpu-badge"></span>
    <button class="action-btn">Reboot Node</button>
  </div>
</template>
```

```javascript
// JavaScript Instantiation:
const template = document.querySelector('#telemetry-card-template');
const container = document.querySelector('#dashboard-grid');

function renderNodeCard(title, cpuUsage) {
  // Clone template contents deeply:
  const clone = template.content.cloneNode(true);

  // Populate dynamic data safely:
  clone.querySelector('.node-title').textContent = title;
  clone.querySelector('.cpu-badge').textContent = `${cpuUsage}% CPU`;
  clone.querySelector('.action-btn').addEventListener('click', () => {
    console.log(`Rebooting ${title}...`);
  });

  container.appendChild(clone);
}
```

---

## 5. Modern Element Mutation Methods

ES6+ introduced clean native mutation methods:

```javascript
const target = document.querySelector('#target');
const newElement = document.createElement('div');

target.before(newElement);      // Inserts newElement directly before target
target.after(newElement);       // Inserts newElement directly after target
target.replaceWith(newElement); // Replaces target with newElement
target.remove();                // Removes target from DOM tree directly
```

---

## 6. XSS-Safe HTML Parsing (`DOMParser` & Sanitizer API)

Never use `element.innerHTML = untrustedUserInput` (which leads to Cross-Site Scripting vulnerabilities!).

Use **`DOMParser`** or safe text assignment:

```javascript
export function parseSafeHtml(htmlString) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(htmlString, 'text/html');

  // Strip all malicious script tags:
  const scripts = doc.querySelectorAll('script, iframe, object, embed');
  scripts.forEach((s) => s.remove());

  return doc.body.children;
}
```

---

## Troubleshooting & Best Practices

1. **`HTMLCollection` (Live) vs `NodeList` (Static)**
   - `getElementsByClassName()` returns a **Live `HTMLCollection`** (modifying the DOM while iterating over it will alter the array length during the loop!).
   - `querySelectorAll()` returns a **Static `NodeList`** (safe for `forEach` iteration).

2. **Always Use `textContent` instead of `innerHTML` for Text**
   Setting `element.textContent = userString` is faster and completely immune to XSS injection because the browser treats the string as raw text rather than parsing HTML tokens.
