# Module 03: The Critical Rendering Path, Reflow, Repaint & GPU Compositing

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Browser Architecture, Critical Rendering Path & 120fps Optimization

---

## 1. The Critical Rendering Path (CRP)

To achieve 60fps (16.6ms per frame) or 120fps (8.3ms per frame) smooth animations, you must master the **Browser Rendering Pipeline**:

```text
The Critical Rendering Path:
[HTML Document] ──► [DOM Tree]
                          │
                          ├─► [Render Tree] ──► [Layout (Reflow)] ──► [Paint] ──► [Composite (GPU)] ──► Display
                          │
[CSS Stylesheet] ──► [CSSOM Tree]
```

1. **DOM Tree**: Parses HTML tokens into structured DOM nodes.
2. **CSSOM Tree**: Parses CSS rules and maps cascading styles to matching selectors.
3. **Render Tree**: Combines DOM and CSSOM, ignoring invisible elements (`display: none`, `<head>`).
4. **Layout (Reflow)**: Calculates the **exact geometry, position (x, y), width, and height** of every visible box on the screen.
5. **Paint**: Rasterizes colors, borders, text glyphs, shadows, and backgrounds into bitmap layers.
6. **Composite**: The **GPU Compositor Thread** aligns and draws independent layers onto the physical screen.

---

## 2. Reflow vs Repaint vs Composite-Only

| Pipeline Stage | CPU / GPU Cost | CSS Properties Triggering This Stage | Performance Impact |
| :--- | :--- | :--- | :--- |
| **Reflow (Layout)** | **Extremely Heavy (CPU)** | `width`, `height`, `margin`, `padding`, `top`, `left`, `fontSize`, `display`, `flex` | Triggers Layout ──► Paint ──► Composite! (Causes frame drops) |
| **Repaint** | **Moderate (CPU Raster)** | `color`, `background-color`, `box-shadow`, `visibility`, `outline` | Skips Layout; triggers Paint ──► Composite |
| **Composite-Only** | **Near-Zero (GPU Hardware)** | **`transform: translate3d()`, `opacity`, `filter`** | **Bypasses CPU Layout AND Paint completely!** (Silky 120fps!) |

```css
/* ❌ SLOW: Triggers expensive CPU Layout and Repaint on every frame tick: */
.animated-box {
  left: 100px;
  top: 50px;
  width: 200px;
}

/* ✅ ULTRA-FAST: Runs 100% on the GPU Compositor thread with zero CPU overhead: */
.animated-box {
  transform: translate3d(100px, 50px, 0) scale(1.2);
  opacity: 0.9;
  will-change: transform, opacity; /* Promotes element to dedicated GPU Layer! */
}
```

---

## 3. Forced Synchronous Layout & Layout Thrashing

### What Is Layout Thrashing?

When JavaScript reads a geometric property (`offsetWidth`, `clientHeight`, `getBoundingClientRect()`), the browser is forced to **synchronously flush all pending layout changes and execute a full reflow on the spot before returning the number**.

If you alternate reading and writing inside a loop:

```javascript
// ❌ CRITICAL BUG: Layout Thrashing (Forces 1,000 Synchronous Reflows!):
const elements = document.querySelectorAll('.card');

for (const el of elements) {
  // READ geometric property (Forces sync reflow!):
  const height = el.clientHeight;

  // WRITE geometric property (Invalidates layout!):
  el.style.height = `${height + 10}px`;
}
```

### The Solution: Batch All Reads First, Then Batch All Writes

```javascript
// ✅ OPTIMIZED: Exactly 1 Reflow!
const elements = document.querySelectorAll('.card');

// Phase 1: Batch all READS
const heights = Array.from(elements, (el) => el.clientHeight);

// Phase 2: Batch all WRITES
elements.forEach((el, index) => {
  el.style.height = `${heights[index] + 10}px`;
});
```

---

## 4. Frame Scheduling with `requestAnimationFrame` (rAF)

Never run visual DOM animations inside `setInterval` or `setTimeout` (which fire out-of-sync with the display hardware refresh rate, dropping frames).

Use **`requestAnimationFrame()`**, which synchronizes your JavaScript callback with the display hardware VSync refresh:

```javascript
class SmoothSpringAnimation {
  constructor(element) {
    this.element = element;
    this.currentX = 0;
    this.targetX = 400;
    this.animationFrameId = null;
  }

  start() {
    const animate = () => {
      // Linear interpolation (Lerp):
      this.currentX += (this.targetX - this.currentX) * 0.08;

      // Apply GPU transform:
      this.element.style.transform = `translate3d(${this.currentX}px, 0, 0)`;

      if (Math.abs(this.targetX - this.currentX) > 0.1) {
        this.animationFrameId = requestAnimationFrame(animate);
      } else {
        this.element.style.transform = `translate3d(${this.targetX}px, 0, 0)`;
      }
    };

    this.animationFrameId = requestAnimationFrame(animate);
  }

  cancel() {
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }
  }
}
```

---

## 5. Background Task Scheduling with `requestIdleCallback` (rIC)

For non-urgent background work (e.g. sending analytics telemetry, pre-fetching search data, index caching), run jobs when the browser is idle:

```javascript
function scheduleBackgroundWork(taskFn) {
  if ('requestIdleCallback' in window) {
    requestIdleCallback(
      (deadline) => {
        // Execute while remaining time in frame budget > 1ms:
        while (deadline.timeRemaining() > 1) {
          const hasMoreWork = taskFn();
          if (!hasMoreWork) break;
        }
      },
      { timeout: 2000 } // Force execution within 2s if browser remains busy
    );
  } else {
    setTimeout(taskFn, 50); // Fallback
  }
}
```

---

## Troubleshooting & Best Practices

1. **Avoid Overusing `will-change`**
   Setting `will-change: transform` promotes an element to its own GPU memory layer. While this accelerates animations, creating hundreds of GPU layers consumes massive VRAM and degrades mobile performance. Apply `will-change` only on active animating components and remove it when the animation completes.

2. **Always Prefer CSS Transforms Over Position/Top/Left**
   Moving elements with `left` or `margin-top` invalidates the document layout, causing 60 reflows per second. Always animate using `transform: translate3d(x, y, 0)`.
