# Module 07: Service Workers, PWAs & Offline Caching Strategies

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Progressive Web Apps, Service Workers & Offline Resiliency

---

## 1. What Is a Service Worker?

A **Service Worker** is an event-driven background worker script registered by the browser that runs completely independent of web pages.

### Architectural Capabilities

1. **Network Interception**: Acts as a client-side programmable network proxy, intercepting all HTTP requests made by the page.
2. **Offline Caching (Cache API)**: Serves static assets and API data even when there is zero internet connectivity.
3. **Background Sync**: Queues failed mutations (e.g. form submits while offline) and retries when internet returns.
4. **Push Notifications**: Displays native OS push notifications even when the browser tab is closed!

```text
Service Worker Proxy Architecture:
[Browser Web Page] ──► [fetch('/api/feed')]
                             │
                             ▼ (Intercepted by Service Worker)
┌─────────────────────────────────────────────────────────────┐
│                    Service Worker Proxy                     │
│                                                             │
│  Is item in Cache? ──► [YES] ──► Return from Cache (0ms!)   │
│         │                                                   │
│        [NO]                                                 │
│         ▼                                                   │
│  Fetch from Remote Server ──► Save to Cache ──► Return Data │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. The Complete Service Worker Lifecycle

```text
┌─────────────────────────────────────────────────────────────┐
│                 Service Worker Lifecycle Flow               │
│                                                             │
│  [1. Register] (`navigator.serviceWorker.register('/sw.js')`)│
│         │                                                   │
│         ▼                                                   │
│  [2. Install Event] ──► Pre-caches static App Shell assets  │
│         │               (`self.skipWaiting()`)              │
│         ▼                                                   │
│  [3. Activate Event] ─► Cleans up old, obsolete caches      │
│         │               (`clients.claim()`)                 │
│         ▼                                                   │
│  [4. Active (Idle)] ──► Intercepts `fetch`, `sync`, `push`  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. The 5 Core Offline Caching Strategies

```text
┌─────────────────────────────────────────────────────────────┐
│                     Caching Strategy Matrix                 │
├────────────────────┬────────────────────────────────────────┤
│ **1. Cache First** │ Checks cache; falls back to network.   │
│                    │ Ideal for static assets (Fonts, Images)│
├────────────────────┼────────────────────────────────────────┤
│ **2. Network First**│ Tries network; falls back to cache if │
│                    │ offline. Ideal for live stock feeds.   │
├────────────────────┼────────────────────────────────────────┤
│ **3. Stale-While-**│ Returns cached version instantly (<5ms)│
│    **Revalidate**  │ while fetching update in background to │
│                    │ update cache for next load.            │
├────────────────────┼────────────────────────────────────────┤
│ **4. Network Only**│ Never caches (e.g. Stripe checkout).   │
├────────────────────┼────────────────────────────────────────┤
│ **5. Cache Only**  │ Pre-cached offline help docs.          │
└────────────────────┴────────────────────────────────────────┘
```

---

## 4. Production Service Worker Implementation (`public/sw.js`)

```javascript
// public/sw.js
const CACHE_VERSION = 'v1.2.0';
const STATIC_CACHE = `static-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `dynamic-${CACHE_VERSION}`;

const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/style.css',
  '/app.js',
  '/manifest.json',
  '/offline.html',
];

// 1. INSTALL EVENT (Pre-cache static assets):
self.addEventListener('install', (event) => {
  console.log('[SW]: Installing & Pre-caching App Shell...');
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => {
      return cache.addAll(STATIC_ASSETS);
    }).then(() => self.skipWaiting()) // Force immediate activation
  );
});

// 2. ACTIVATE EVENT (Purge old cache versions):
self.addEventListener('activate', (event) => {
  console.log('[SW]: Activating new Service Worker version...');
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys
          .filter((k) => k !== STATIC_CACHE && k !== DYNAMIC_CACHE)
          .map((k) => {
            console.log(`[SW]: Purging obsolete cache: ${k}`);
            return caches.delete(k);
          })
      );
    }).then(() => self.clients.claim()) // Take control of all open browser tabs immediately!
  );
});

// 3. FETCH EVENT (Routing & Strategy Engine):
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // A. Static Assets: Cache-First Strategy
  if (STATIC_ASSETS.includes(url.pathname)) {
    event.respondWith(
      caches.match(request).then((cached) => cached || fetch(request))
    );
    return;
  }

  // B. Dynamic API Requests: Stale-While-Revalidate Strategy
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      caches.open(DYNAMIC_CACHE).then(async (cache) => {
        const cachedResponse = await cache.match(request);

        // Fetch fresh copy in background:
        const networkFetch = fetch(request)
          .then((networkResponse) => {
            if (networkResponse.ok) {
              cache.put(request, networkResponse.clone());
            }
            return networkResponse;
          })
          .catch(() => {
            // Return cached copy if offline:
            if (cachedResponse) return cachedResponse;
            return new Response(JSON.stringify({ error: 'Offline', offline: true }), {
              headers: { 'Content-Type': 'application/json' },
            });
          });

        return cachedResponse || networkFetch;
      })
    );
    return;
  }

  // C. HTML Navigation: Network-First with Offline Fallback
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => caches.match('/offline.html'))
    );
  }
});
```

---

## 5. Registering the Service Worker in Main App

```javascript
// src/main.js
export async function registerServiceWorker() {
  if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
    try {
      const registration = await navigator.serviceWorker.register('/sw.js', {
        scope: '/',
      });

      registration.onupdatefound = () => {
        const installingWorker = registration.installing;
        installingWorker.onstatechange = () => {
          if (installingWorker.state === 'installed' && navigator.serviceWorker.controller) {
            console.log('New app version available! Prompt user to reload.');
          }
        };
      };

      console.log('[SW]: Registered with scope:', registration.scope);
    } catch (err) {
      console.error('[SW Registration Error]:', err);
    }
  }
}
```

---

## 6. Web App Manifest (`public/manifest.json`)

To enable native "Install to Home Screen" on iOS, Android, and Desktop:

```json
{
  "name": "Enterprise Cloud Platform",
  "short_name": "CloudPlatform",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0f172a",
  "theme_color": "#4f46e5",
  "icons": [
    {
      "src": "/icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

---

## Troubleshooting & Best Practices

1. **HTTPS Is Mandatory**
   Service Workers **only execute over HTTPS** (with the sole exception of `http://localhost` for local development) to prevent Man-In-The-Middle network interception.

2. **Clone Responses Before Caching (`response.clone()`)**
   A `Response` object's body is a one-time readable stream. If you pass `response` to `cache.put()` and also return it to the browser, it will throw `TypeError: Body has already been consumed`. Always call `response.clone()`.
