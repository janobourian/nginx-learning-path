# Module 16: Client-Side Routing — History API & The Modern Navigation API

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Single-Page App Architecture, History API & Navigation Standards

---

## 1. Single Page Application (SPA) Routing Mechanics

In traditional multi-page websites, clicking a link triggers a full browser reload and downloads a new HTML document from the server.

In a **Single Page Application (SPA)**:

1. The initial HTML/JS shell loads once.
2. Clicking a navigation link is intercepted by JavaScript.
3. The URL in the address bar is updated **without refreshing the page**.
4. The router renders the corresponding component view dynamically into the DOM.

```text
SPA Client-Side Routing Pipeline:
[User Clicks Link: <a href="/dashboard">]
        │
        ▼ (Intercepted by Router `preventDefault()`)
[history.pushState(null, '', '/dashboard')] ──► Updates URL bar instantly (0ms!)
        │
        ▼
[Router matches '/dashboard'] ──► Renders DashboardView Component into <main id="app">
```

---

## 2. The HTML5 History API (`pushState` vs `replaceState`)

```javascript
// 1. pushState: Adds a new entry to the browser's navigation history stack:
history.pushState({ pageId: 'analytics' }, 'Analytics', '/analytics');

// 2. replaceState: Overwrites current history entry (does not create back-button history):
history.replaceState({ pageId: 'settings' }, 'Settings', '/settings');

// 3. Listening to Browser Back / Forward Buttons (popstate):
window.addEventListener('popstate', (event) => {
  console.log('[Router]: User clicked Back/Forward button!');
  console.log('Restored State:', event.state);
  console.log('New Path:', window.location.pathname);
  // Re-render matching route view:
  renderCurrentRoute();
});
```

---

## 3. Building a Production Vanilla Client-Side Router

Let's build a modular client-side router with dynamic route parameters (`/users/:id`), link click interception, and page rendering:

```javascript
// src/router/vanilla_router.js

export class VanillaRouter {
  constructor(routes, rootContainer) {
    this.routes = routes; // Array of { path, view }
    this.root = rootContainer;

    this._initListeners();
    this.navigate(window.location.pathname, false);
  }

  _initListeners() {
    // 1. Listen for browser Back/Forward navigation:
    window.addEventListener('popstate', () => {
      this._renderRoute(window.location.pathname);
    });

    // 2. Intercept internal anchor link clicks globally:
    document.addEventListener('click', (event) => {
      const anchor = event.target.closest('a[href]');
      if (!anchor) return;

      const href = anchor.getAttribute('href');
      // Only intercept internal relative links (ignore external http:// and target="_blank"):
      if (href.startsWith('/') && !anchor.target) {
        event.preventDefault();
        this.navigate(href);
      }
    });
  }

  navigate(pathname, pushToHistory = true) {
    if (pushToHistory && window.location.pathname !== pathname) {
      history.pushState(null, '', pathname);
    }
    this._renderRoute(pathname);
  }

  _renderRoute(pathname) {
    for (const route of this.routes) {
      const match = this._matchPath(route.path, pathname);
      if (match) {
        console.log(`[Router]: Navigated to '${pathname}'`);
        this.root.innerHTML = '';
        this.root.appendChild(route.view(match.params));
        window.scrollTo(0, 0); // Scroll restoration to top
        return;
      }
    }

    // 404 Route Fallback:
    this.root.innerHTML = '<h1>404 — Page Not Found</h1>';
  }

  _matchPath(routePattern, currentPath) {
    // Converts '/users/:id/edit' into Regex: ^\/users\/([^\/]+)\/edit$
    const paramNames = [];
    const regexPattern = routePattern.replace(/:([a-zA-Z0-9_]+)/g, (_, key) => {
      paramNames.push(key);
      return '([^/]+)';
    });

    const regex = new RegExp(`^${regexPattern}$`);
    const match = currentPath.match(regex);

    if (!match) return null;

    const params = {};
    paramNames.forEach((name, index) => {
      params[name] = match[index + 1];
    });

    return { params };
  }
}
```

```javascript
// Application Setup:
const routes = [
  {
    path: '/',
    view: () => {
      const div = document.createElement('div');
      div.innerHTML = '<h2>Home Dashboard</h2><a href="/users/101">View User #101</a>';
      return div;
    },
  },
  {
    path: '/users/:id',
    view: (params) => {
      const div = document.createElement('div');
      div.innerHTML = `<h2>User Profile: ${params.id}</h2><a href="/">Back to Home</a>`;
      return div;
    },
  },
];

const router = new VanillaRouter(routes, document.querySelector('#app-main'));
```

---

## 4. The Modern Navigation API (`window.navigation`)

Modern browsers introduce the **Navigation API**, which consolidates `pushState`, `popstate`, and form submissions into a single declarative handler:

```javascript
if ('navigation' in window) {
  window.navigation.addEventListener('navigate', (event) => {
    // Check if navigation can be intercepted (same-origin, not download):
    if (!event.canIntercept || event.hashChange || event.downloadRequest) return;

    const destinationUrl = new URL(event.destination.url);

    // Intercept navigation seamlessly:
    event.intercept({
      async handler() {
        console.log(`[Navigation API]: Transitioning to ${destinationUrl.pathname}`);
        // Fetch view and update DOM:
        await renderPage(destinationUrl.pathname);
      },
    });
  });
}
```

---

## Troubleshooting & Best Practices

1. **Server-Side Fallback Configuration (Nginx / Cloudflare)**
   When users refresh `/users/101` in their browser, the server must be configured with a fallback rule (`try_files $uri $uri/ /index.html;`) so that Nginx returns `index.html` instead of a 404 error, allowing the client-side router to boot and resolve the path.

2. **Always Scroll to Top on Navigation**
   When navigating to a new route in an SPA, the browser maintains the previous scroll position unless you explicitly call `window.scrollTo(0, 0)`.
