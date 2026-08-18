# Module 12: HTML5 Canvas 2D, Particle Physics & `OffscreenCanvas`

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** 2D Graphics, Canvas Rendering & High-Performance Particle Physics

---

## 1. The Canvas 2D Rendering Pipeline

While the DOM represents UI as a hierarchical tree of boxes, the **HTML5 `<canvas>`** element provides an immediate-mode 2D pixel raster surface.

```
Canvas 2D Immediate Mode Loop:
┌─────────────────────────────────────────────────────────────┐
│ 1. Clear Frame (`ctx.clearRect(0, 0, width, height)`)       │
│                                                             │
│ 2. Save Context State (`ctx.save()`)                        │
│                                                             │
│ 3. Calculate Physics & Positions (`x += vx * dt`)           │
│                                                             │
│ 4. Draw Geometry, Gradients & Paths (`ctx.arc`, `ctx.fill`) │
│                                                             │
│ 5. Restore Context State (`ctx.restore()`)                  │
│                                                             │
│ 6. Schedule Next Frame (`requestAnimationFrame(loop)`)      │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. High-DPI (Retina) Scaling

On high-DPI displays (Device Pixel Ratio > 1), canvas rendering becomes blurry unless scaled to physical hardware pixels:

```javascript
export function setupHighDpiCanvas(canvas, cssWidth, cssHeight) {
  const dpr = window.devicePixelRatio || 1;

  // Set internal buffer resolution to physical pixels:
  canvas.width = cssWidth * dpr;
  canvas.height = cssHeight * dpr;

  // Set display size in CSS logical pixels:
  canvas.style.width = `${cssWidth}px`;
  canvas.style.height = `${cssHeight}px`;

  const ctx = canvas.getContext('2d');
  // Scale drawing operations by DPR automatically:
  ctx.scale(dpr, dpr);

  return ctx;
}
```

---

## 3. High-Performance Particle Physics Engine (5,000 Interactive Particles)

Let's build a glowing interactive particle system with physics velocity, friction, spring dynamics, and mouse repulsion:

```javascript
// src/graphics/particle_system.js

class Particle {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.originX = x;
    this.originY = y;
    this.vx = (Math.random() - 0.5) * 2;
    this.vy = (Math.random() - 0.5) * 2;
    this.radius = Math.random() * 2.5 + 1;
    this.color = `hsl(${Math.random() * 60 + 220}, 100%, 65%)`; // Glowing Cyan/Indigo
    this.friction = 0.95;
    this.springFactor = 0.02;
  }

  update(mouse, canvasWidth, canvasHeight) {
    // 1. Calculate distance from cursor:
    const dx = mouse.x - this.x;
    const dy = mouse.y - this.y;
    const distance = Math.hypot(dx, dy);

    // 2. Mouse Repulsion Force (Push particles away within 120px):
    if (distance < 120) {
      const force = (120 - distance) / 120;
      const angle = Math.atan2(dy, dx);
      this.vx -= Math.cos(angle) * force * 5;
      this.vy -= Math.sin(angle) * force * 5;
    }

    // 3. Spring force returning particle to origin:
    const returnDx = this.originX - this.x;
    const returnDy = this.originY - this.y;
    this.vx += returnDx * this.springFactor;
    this.vy += returnDy * this.springFactor;

    // 4. Apply velocity & friction:
    this.vx *= this.friction;
    this.vy *= this.friction;
    this.x += this.vx;
    this.y += this.vy;
  }

  draw(ctx) {
    ctx.beginPath();
    ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
    ctx.fillStyle = this.color;
    ctx.fill();
  }
}

export class ParticleEngine {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.particles = [];
    this.mouse = { x: -1000, y: -1000 };
    this.isRunning = false;

    this._initEvents();
  }

  initGrid(cols = 40, rows = 30) {
    this.particles = [];
    const spacingX = this.canvas.width / cols;
    const spacingY = this.canvas.height / rows;

    for (let x = 0; x < cols; x++) {
      for (let y = 0; y < rows; y++) {
        this.particles.push(new Particle(x * spacingX + spacingX / 2, y * spacingY + spacingY / 2));
      }
    }
  }

  _initEvents() {
    this.canvas.addEventListener('mousemove', (e) => {
      const rect = this.canvas.getBoundingClientRect();
      this.mouse.x = e.clientX - rect.left;
      this.mouse.y = e.clientY - rect.top;
    });

    this.canvas.addEventListener('mouseleave', () => {
      this.mouse.x = -1000;
      this.mouse.y = -1000;
    });
  }

  start() {
    this.isRunning = true;
    let lastTime = performance.now();

    const loop = (currentTime) => {
      if (!this.isRunning) return;

      const dt = (currentTime - lastTime) / 1000;
      lastTime = currentTime;

      // 1. Semi-transparent black clear for particle motion blur trails:
      this.ctx.fillStyle = 'rgba(15, 23, 42, 0.25)';
      this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

      // 2. Additive Blending for high-tech neon glow:
      this.ctx.globalCompositeOperation = 'lighter';

      // 3. Update & Draw all particles:
      for (let i = 0; i < this.particles.length; i++) {
        const p = this.particles[i];
        p.update(this.mouse, this.canvas.width, this.canvas.height);
        p.draw(this.ctx);
      }

      this.ctx.globalCompositeOperation = 'source-over';
      requestAnimationFrame(loop);
    };

    requestAnimationFrame(loop);
  }

  stop() {
    this.isRunning = false;
  }
}
```

---

## 4. `OffscreenCanvas` & Multi-Threaded Background Rendering

Rendering 50,000 particles on the main thread can cause UI touch latency.

Using **`OffscreenCanvas`**, you can transfer control of the `<canvas>` DOM element to a **Web Worker**, executing all canvas drawing **100% in a background thread**:

```javascript
// Main Thread:
const canvas = document.querySelector('#heavy-canvas');
// Transfer canvas drawing control to background worker:
const offscreen = canvas.transferControlToOffscreen();

const worker = new Worker('canvas_worker.js', { type: 'module' });
worker.postMessage({ canvas: offscreen }, [offscreen]); // ◄── Transferred!
```

```javascript
// Inside canvas_worker.js:
self.onmessage = (event) => {
  const offscreenCanvas = event.data.canvas;
  const ctx = offscreenCanvas.getContext('2d');

  function renderLoop() {
    ctx.clearRect(0, 0, offscreenCanvas.width, offscreenCanvas.height);
    // Draw 50,000 particles in background worker!
    requestAnimationFrame(renderLoop);
  }

  requestAnimationFrame(renderLoop);
};
```

---

## Troubleshooting & Best Practices

1. **Minimize Context State Changes**
   Changing `ctx.fillStyle` or `ctx.shadowBlur` thousands of times per frame forces the GPU to flush draw batches. Group particles by color/brush and draw them in batches before changing styles.

2. **Always Use `ctx.save()` / `ctx.restore()` Around Transforms**
   If you apply `ctx.translate()` or `ctx.rotate()` without wrapping in `ctx.save()` and `ctx.restore()`, transformations will accumulate exponentially on every frame tick!
