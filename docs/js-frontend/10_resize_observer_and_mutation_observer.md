# Module 10: DOM Observers — `ResizeObserver`, `MutationObserver` & Container Queries

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Observer APIs, Element Resizing & DOM Mutation Tracking

---

## 1. The Modern DOM Observer Suite

While `IntersectionObserver` (Module 09) tracks viewport visibility, modern web applications rely on two additional observer APIs:

```text
┌─────────────────────────────────────────────────────────────┐
│                 DOM Observer API Matrix                     │
├────────────────────┬────────────────────────────────────────┤
│ **`ResizeObserver`**│ Tracks changes to an element's         │
│                    │ **content box, border box, or pixel    │
│                    │ dimensions** in real-time.             │
├────────────────────┼────────────────────────────────────────┤
│ **`MutationObserver`│ Tracks changes to the **DOM tree       │
│                    │ structure** (added/removed child nodes,│
│                    │ attribute changes, text modifications).│
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Element Dimensions with `ResizeObserver`

Historically, detecting element resizing required listening to `window.addEventListener('resize')`. However, elements resize due to many reasons *other* than browser window changes (e.g. sidebar collapse, dynamic content insertion, CSS flexbox shifts).

`ResizeObserver` observes the exact dimensions of individual elements:

```javascript
// src/components/responsive_container.js
const card = document.querySelector('.responsive-card');

const resizeObserver = new ResizeObserver((entries) => {
  for (const entry of entries) {
    // 1. Content Box Size (Width/Height excluding padding & border):
    const { inlineSize: width, blockSize: height } = entry.contentBoxSize[0];

    console.log(`[ResizeObserver]: Card resized to ${width}px x ${height}px`);

    // 2. JavaScript Container Queries (Adapt UI based on element size):
    if (width > 600) {
      entry.target.classList.add('card-wide');
      entry.target.classList.remove('card-compact');
    } else {
      entry.target.classList.add('card-compact');
      entry.target.classList.remove('card-wide');
    }
  }
});

resizeObserver.observe(card);
```

---

## 3. Crisp High-DPI Canvas Rendering (`devicePixelContentBoxSize`)

When drawing to an HTML `<canvas>`, rendering on Retina / 4K displays often looks blurry because of subpixel scaling.

Use **`devicePixelContentBoxSize`** to match canvas resolution to the physical device screen pixels exactly:

```javascript
const canvas = document.querySelector('#telemetry-chart');
const ctx = canvas.getContext('2d');

const canvasObserver = new ResizeObserver((entries) => {
  const entry = entries[0];

  if (entry.devicePixelContentBoxSize) {
    // Exact physical hardware pixels on high-DPI display:
    const width = entry.devicePixelContentBoxSize[0].inlineSize;
    const height = entry.devicePixelContentBoxSize[0].blockSize;

    canvas.width = width;
    canvas.height = height;

    // Draw sharp, non-blurry graphics:
    ctx.fillStyle = '#4f46e5';
    ctx.fillRect(0, 0, width, height);
  }
});

canvasObserver.observe(canvas, { box: 'device-pixel-content-box' });
```

---

## 4. Tracking Tree Changes with `MutationObserver`

`MutationObserver` replaces deprecated legacy mutation events (`DOMNodeInserted`, `DOMAttrModified`), monitoring DOM modifications asynchronously:

```javascript
// src/security/dom_guard.js
const targetContainer = document.querySelector('#secure-checkout-container');

const mutationObserver = new MutationObserver((mutationsList, observer) => {
  for (const mutation of mutationsList) {
    // 1. Child Nodes Added or Removed:
    if (mutation.type === 'childList') {
      mutation.addedNodes.forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          // Detect injected malicious third-party script tags:
          if (node.tagName === 'SCRIPT' || node.tagName === 'IFRAME') {
            console.warn('🚨 Security Alert: Unauthorized script injection detected. Removing node!');
            node.remove();
          }
        }
      });
    }

    // 2. Attribute Mutations (e.g. tracking dynamic theme changes):
    if (mutation.type === 'attributes') {
      console.log(`Attribute '${mutation.attributeName}' changed on:`, mutation.target);
    }
  }
});

// Configure exact observation targets:
mutationObserver.observe(targetContainer, {
  childList: true,       // Observe direct children additions/removals
  subtree: true,         // Observe all nested descendant nodes deeply!
  attributes: true,      // Observe attribute modifications
  attributeFilter: ['class', 'data-theme', 'disabled'], // Whitelist observed attributes
  attributeOldValue: true,
});
```

---

## 5. Avoiding the "ResizeObserver Loop Limit Exceeded" Error

If your `ResizeObserver` callback directly modifies the DOM in a way that triggers another resize on the observed element within the same frame tick, the browser will log a `ResizeObserver loop limit exceeded` warning.

### Solution: Debounce with `requestAnimationFrame`

```javascript
let pendingEntries = null;

const safeObserver = new ResizeObserver((entries) => {
  pendingEntries = entries;

  requestAnimationFrame(() => {
    if (!pendingEntries) return;
    for (const entry of pendingEntries) {
      // Modify DOM safely inside the next animation frame tick:
      entry.target.style.fontSize = `${entry.contentRect.width / 20}px`;
    }
    pendingEntries = null;
  });
});
```

---

## Troubleshooting & Best Practices

1. **Be Granular with `MutationObserver` Options**
   Enabling `{ subtree: true, characterData: true, attributes: true }` on `document.body` monitors every keystroke and class change across the entire webpage, degrading CPU performance. Scope `MutationObserver` to specific small container elements.

2. **Clean Up Observers on Component Unmount**
   Always invoke `resizeObserver.disconnect()` and `mutationObserver.disconnect()` when tearing down UI components.
