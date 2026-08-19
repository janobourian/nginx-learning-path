# Module 17: Frontend Performance & Google Core Web Vitals (LCP, INP, CLS)

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Performance Engineering, Core Web Vitals & Main-Thread Scheduling

---

## 1. The 3 Google Core Web Vitals (CWV)

**Core Web Vitals** are Google's standardized metrics for measuring real-world user experience and SEO ranking:

```text
┌─────────────────────────────────────────────────────────────┐
│                 Google Core Web Vitals Matrix               │
├────────────────────┬──────────────────┬─────────────────────┤
│ Metric             │ Target (Good)    │ What It Measures    │
├────────────────────┼──────────────────┼─────────────────────┤
│ **LCP** (Largest   │ **< 2.5 seconds**│ **Loading Speed**:  │
│ Contentful Paint)  │                  │ Time until largest  │
│                    │                  │ image/text renders. │
├────────────────────┼──────────────────┼─────────────────────┤
│ **INP** (Interaction│ **< 200 ms**    │ **Responsiveness**: │
│ to Next Paint)     │                  │ UI latency on clicks│
│                    │                  │ and keyboard taps.  │
├────────────────────┼──────────────────┼─────────────────────┤
│ **CLS** (Cumulative│ **< 0.1**        │ **Visual Stability**:│
│ Layout Shift)      │                  │ Unexpected layout   │
│                    │                  │ shifting of content.│
└────────────────────┴──────────────────┴─────────────────────┘
```

---

## 2. Measuring Core Web Vitals Programmatically (`PerformanceObserver`)

Modern browsers expose the **`PerformanceObserver`** API to monitor real-user metrics (RUM) in JavaScript:

```javascript
// src/telemetry/web_vitals.js

// 1. Measure LCP (Largest Contentful Paint):
new PerformanceObserver((entryList) => {
  const entries = entryList.getEntries();
  const lastEntry = entries[entries.length - 1];
  console.log(`[CWV]: LCP = ${lastEntry.startTime.toFixed(2)} ms (Target: < 2500ms)`, lastEntry.element);
}).observe({ type: 'largest-contentful-paint', buffered: true });

// 2. Measure CLS (Cumulative Layout Shift):
let clsScore = 0;
new PerformanceObserver((entryList) => {
  for (const entry of entryList.getEntries()) {
    // Only count shifts not caused by recent user interactions:
    if (!entry.hadRecentInput) {
      clsScore += entry.value;
      console.log(`[CWV]: CLS Score = ${clsScore.toFixed(4)} (Target: < 0.10)`);
    }
  }
}).observe({ type: 'layout-shift', buffered: true });

// 3. Measure INP (Interaction to Next Paint):
new PerformanceObserver((entryList) => {
  for (const entry of entryList.getEntries()) {
    const duration = entry.duration;
    console.log(`[CWV]: INP = ${duration.toFixed(2)} ms (Target: < 200ms) on`, entry.name);
  }
}).observe({ type: 'event', buffered: true, durationThreshold: 16 });
```

---

## 3. High-Impact CWV Optimization Playbook

### Optimizing LCP (< 2.5s)

1. **`fetchpriority="high"` on Hero Images**: Tells the browser preload scanner to prioritize the LCP hero banner over secondary CSS/JS scripts:

   ```html
   <img src="/hero-banner.webp" fetchpriority="high" alt="Platform Dashboard">
   ```

2. **Preload Critical Web Fonts**:

   ```html
   <link rel="preload" href="/fonts/inter.woff2" as="font" type="font/woff2" crossorigin>
   ```

---

### Optimizing CLS (< 0.1)

1. **Explicit Dimensions on All Images & Embeds**: Never omit `width` and `height` attributes (which causes zero-height containers that suddenly expand when images load, shifting the whole page):

   ```html
   <!-- ✅ Browser reserves aspect ratio space immediately: -->
   <img src="card.png" width="800" height="450" style="aspect-ratio: 16 / 9; width: 100%; height: auto;">
   ```

2. **Reserve Ad & Banner Slots with CSS `min-height`**:

   ```css
   .ad-slot-container {
     min-height: 250px; /* Prevents text below from jumping when ad loads! */
   }
   ```

---

### Optimizing INP (< 200ms) with `scheduler.yield()`

When a user clicks a button and JavaScript runs a heavy 300ms computation, the main thread is blocked, preventing the browser from rendering the button's clicked visual state.

Use **`scheduler.yield()`** (Chrome 129+ standard) to **yield execution back to the browser to paint intermediate UI frames**:

```javascript
// src/performance/task_scheduler.js

async function yieldToMainThread() {
  if ('scheduler' in window && 'yield' in window.scheduler) {
    return await window.scheduler.yield();
  }
  // Fallback for older browsers:
  return new Promise((resolve) => setTimeout(resolve, 0));
}

export async function processHeavyListWithZeroInp(items) {
  for (let i = 0; i < items.length; i++) {
    // Process item:
    heavyCalculations(items[i]);

    // Every 50 items, yield control to allow browser to handle clicks/scrolling:
    if (i % 50 === 0) {
      await yieldToMainThread();
    }
  }
}
```

---

## Troubleshooting & Best Practices

1. **`font-display: swap` for Web Fonts**
   Setting `font-display: swap` prevents FOIT (Flash of Invisible Text), rendering system fonts immediately while the web font downloads.

2. **Audit Real User Metrics (RUM)**
   Synthetic Lab metrics (Lighthouse) run on simulated clean networks and fast machines. Always use Real User Monitoring (`web-vitals` library) to capture metrics across low-end mobile devices and spotty cellular networks.
