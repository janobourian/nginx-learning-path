# Module 09: `IntersectionObserver` — Lazy Loading, Infinite Scroll & Viewability

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** Observer APIs, Viewport Intersection & Performance Engineering

---

## 1. Why `IntersectionObserver` Replaced Scroll Event Listeners

In legacy web applications, detecting when an element scrolled into view required attaching a `scroll` event listener and calling `element.getBoundingClientRect()`:

```javascript
// ❌ HORRIBLE LEGACY CODE:
window.addEventListener('scroll', () => {
  const rect = element.getBoundingClientRect(); // 💥 Forces Synchronous Layout Reflow on every pixel scrolled!
});
```

The **`IntersectionObserver`** API executes **asynchronously on the browser compositor thread**, notifying your JavaScript code only when an element enters or exits a specified viewport threshold with **zero main-thread scroll jank**:

```
IntersectionObserver Mechanics:
[Scrollable Viewport (Root)]
       │
       ▼ (Root Margin: '200px' Pre-fetch Zone)
┌─────────────────────────────────────────────────────────────┐
│ [Target Element approaching viewport...]                   │
│ ──► IntersectionObserver triggers callback asynchronously!   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Setting Up an `IntersectionObserver`

```javascript
const options = {
  root: null, // null = Browser viewport (or pass a scrollable container element)
  rootMargin: '200px 0px', // Trigger 200px BEFORE element enters screen (Pre-fetch zone!)
  threshold: [0.0, 0.5, 1.0], // Triggers at 0% visible, 50% visible, and 100% fully visible
};

const observer = new IntersectionObserver((entries, observerInstance) => {
  for (const entry of entries) {
    console.log('Target:', entry.target);
    console.log('Is Intersecting:', entry.isIntersecting);
    console.log('Intersection Ratio:', entry.intersectionRatio); // e.g. 0.75 (75% visible)
    console.log('Bounding Rect:', entry.boundingClientRect);
  }
}, options);

// Observe DOM element:
observer.observe(document.querySelector('#target-card'));
```

---

## 3. Production Use Case 1: High-Performance Image Lazy Loading

Load high-resolution images and videos only when they are about to scroll into view:

```html
<img
  class="lazy-image"
  src="/placeholder-blur.jpg"
  data-src="https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=1600"
  alt="High-Res Landscape"
/>
```

```javascript
// src/components/lazy_images.js
export function initializeLazyImages() {
  const lazyImages = document.querySelectorAll('img.lazy-image');

  const imageObserver = new IntersectionObserver(
    (entries, observer) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          const img = entry.target;
          const realSrc = img.dataset.src;

          if (realSrc) {
            // Swap placeholder with real image:
            img.src = realSrc;
            img.classList.add('loaded');
          }

          // Unobserve after loading to free memory:
          observer.unobserve(img);
        }
      }
    },
    { rootMargin: '300px 0px' } // Pre-load 300px before reaching screen!
  );

  lazyImages.forEach((img) => imageObserver.observe(img));
}
```

---

## 4. Production Use Case 2: Infinite Scrolling with Sentinel Nodes

Instead of calculating complex scroll offsets, place an invisible **Sentinel Node** at the bottom of the list:

```html
<div id="feed-container">
  <!-- Dynamic cards appended here -->
</div>

<!-- Invisible Sentinel: -->
<div id="infinite-scroll-sentinel" style="height: 20px;"></div>
```

```javascript
// src/features/feed/infinite_scroll.js
let currentPage = 1;
let isLoading = false;

const sentinel = document.querySelector('#infinite-scroll-sentinel');
const feedContainer = document.querySelector('#feed-container');

const infiniteScrollObserver = new IntersectionObserver(
  async (entries) => {
    const entry = entries[0];
    if (entry.isIntersecting && !isLoading) {
      isLoading = true;
      console.log(`Loading Page #${currentPage}...`);

      const items = await fetchMoreFeedItems(currentPage);
      renderFeedItems(items);

      currentPage++;
      isLoading = false;
    }
  },
  { rootMargin: '400px' } // Trigger 400px before user hits bottom!
);

infiniteScrollObserver.observe(sentinel);
```

---

## 5. Production Use Case 3: Ad Viewability & Read-Time Analytics

Verify when an advertisement or article section was **at least 50% visible for at least 1 consecutive second**:

```javascript
export function trackAdViewability(adElement, onAdViewed) {
  let timer = null;

  const adObserver = new IntersectionObserver(
    (entries) => {
      const entry = entries[0];

      if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
        // Start 1-second viewability timer:
        timer = setTimeout(() => {
          onAdViewed(adElement.id);
          adObserver.disconnect(); // Metric tracked once
        }, 1000);
      } else {
        // If user quickly scrolls past in < 1 second, cancel timer:
        clearTimeout(timer);
      }
    },
    { threshold: 0.5 }
  );

  adObserver.observe(adElement);
}
```

---

## Troubleshooting & Best Practices

1. **Always `unobserve()` Single-Use Elements**
   Once an image is loaded or an entrance animation is triggered, call `observer.unobserve(entry.target)` to eliminate redundant observer tracking.

2. **Always Disconnect Observers in Single Page Apps**
   When switching routes in a React/Vue/Svelte SPA, call `observer.disconnect()` in the component unmount hook to prevent memory leaks from detached DOM nodes.
