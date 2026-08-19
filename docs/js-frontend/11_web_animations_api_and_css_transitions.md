# Module 11: The Web Animations API (WAAPI) & Scroll-Driven Animations

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Motion Design, GPU Animation Pipelines & WAAPI

---

## 1. Why the Web Animations API (WAAPI) Is Superior

Historically, frontend developers were forced to choose between:

- **CSS Animations (`@keyframes`)**: High performance (runs on GPU Compositor), but rigid and difficult to dynamically control or synchronize via JavaScript.
- **JavaScript Animations (`rAF` / GSAP)**: Flexible programmatic control, but runs on the main thread and can suffer from scroll stutter and frame drops.

The **Web Animations API (WAAPI)** unites both worlds:

- It exposes the browser's **internal native CSS animation engine to JavaScript**.
- Gives full programmatic playback control (`play()`, `pause()`, `reverse()`, `currentTime`, `playbackRate`).
- Executes **100% on the GPU Compositor Thread** when animating `transform` and `opacity`!

```text
Animation Performance Comparison:
JS setInterval/rAF: [Main JS Thread (CPU)] ──► [Layout] ──► [Paint] ──► Display (High CPU)
WAAPI (transform):  [Direct GPU Compositor Engine] ───────────────────► Display (Zero Main-Thread CPU!)
```

---

## 2. Basic WAAPI Animation (`element.animate()`)

```javascript
const card = document.querySelector('.hero-card');

// 1. Define Keyframes:
const keyframes = [
  { transform: 'scale(0.8) translateY(50px)', opacity: 0, filter: 'blur(10px)' },
  { transform: 'scale(1.05) translateY(-5px)', opacity: 0.8, offset: 0.7 }, // 70% timestamp
  { transform: 'scale(1) translateY(0)', opacity: 1, filter: 'blur(0px)' },
];

// 2. Configure Timing Options:
const options = {
  duration: 1000,           // 1000ms duration
  easing: 'cubic-bezier(0.16, 1, 0.3, 1)', // Spring-like ease-out curve
  fill: 'forwards',         // Retain final state after animation ends
  iterations: 1,
};

// 3. Play Animation:
const animation = card.animate(keyframes, options);
```

---

## 3. Programmatic Playback & Timeline Scrubbing

An `Animation` instance provides fine-grained controls:

```javascript
const anim = card.animate(keyframes, { duration: 2000, fill: 'both' });

// Playback Controls:
anim.pause();
anim.play();
anim.reverse(); // Smoothly animates backward!

// Dynamic Speed Control (Slow motion & fast forward):
anim.playbackRate = 0.5; // 50% slow motion
anim.playbackRate = 2.0; // 2x speed

// Timeline Scrubbing:
anim.currentTime = 500; // Jump directly to 500ms timestamp!

// Promise-based Lifecycle:
await anim.finished;
console.log('Animation completed cleanly!');
```

---

## 4. Staggered Animations Across Element Collections

Animate a list of elements with staggered time offsets:

```javascript
export function animateStaggeredList(selector, staggerDelayMs = 80) {
  const elements = document.querySelectorAll(selector);

  elements.forEach((element, index) => {
    element.animate(
      [
        { opacity: 0, transform: 'translateY(30px)' },
        { opacity: 1, transform: 'translateY(0)' },
      ],
      {
        duration: 600,
        delay: index * staggerDelayMs, // ◄── Staggered start delay!
        easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)',
        fill: 'forwards',
      }
    );
  });
}
```

---

## 5. Scroll-Driven Animations API (`ScrollTimeline` & `ViewTimeline`)

Modern browsers support **Scroll-Driven Animations**, binding an animation's timeline directly to the user's scroll progress **with 0ms JavaScript execution on scroll**:

```javascript
// Bind progress bar animation directly to whole-page scroll:
const progressBar = document.querySelector('#reading-progress');

progressBar.animate(
  { transform: ['scaleX(0)', 'scaleX(1)'] },
  {
    fill: 'both',
    timeline: new ScrollTimeline({
      source: document.documentElement,
      axis: 'block',
    }),
  }
);
```

### View-Based Scroll Animation (`ViewTimeline`)

Animate an element as it enters and travels through the viewport:

```javascript
const featureImage = document.querySelector('.feature-image');

featureImage.animate(
  [
    { opacity: 0, transform: 'scale(0.8)' },
    { opacity: 1, transform: 'scale(1)' },
  ],
  {
    fill: 'both',
    timeline: new ViewTimeline({
      subject: featureImage,
      axis: 'block',
    }),
    rangeStart: 'entry 0%',   // Starts when element enters bottom of screen
    rangeEnd: 'cover 50%',    // Reaches 100% when element is halfway up the screen
  }
);
```

---

## Troubleshooting & Best Practices

1. **Always Animate Compositor-Friendly Properties**
   To guarantee 120fps GPU performance, restrict animated properties to **`transform`**, **`opacity`**, and **`filter`**. Animating `height`, `top`, or `margin` forces the CPU to calculate 120 layout reflows per second.

2. **Clean Up Infinite Animations**
   If an element has an infinite animation (`iterations: Infinity`) and the element is removed from the DOM, call `animation.cancel()` to free CPU/GPU animation clock cycles.
