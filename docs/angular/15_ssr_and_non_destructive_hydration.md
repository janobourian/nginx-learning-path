# Module 15: Server-Side Rendering (SSR) & Non-Destructive Hydration

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** Server-Side Rendering, Hydration & Event Replay

---

## 1. The Evolution of Angular SSR

Historically (Angular v2–v15), Server-Side Rendering via Angular Universal suffered from **Destructive Hydration**:
1. The Node.js server pre-rendered the application into HTML.
2. The browser received the HTML and painted it on screen.
3. When client-side Angular loaded, it **completely destroyed all server-rendered DOM nodes** and re-created brand new DOM elements from scratch.
4. This caused visible layout flicker, lost focus in text inputs, and dropped user clicks.

In modern Angular (v16+):
- **Non-Destructive Hydration**: Angular inspects the existing server-rendered DOM nodes and attaches event listeners directly to them without re-creating a single DOM element!
- **Event Replay (`withEventReplay()`)**: Captures user clicks and form interactions that occurred *before* the client JavaScript finished downloading and replays them seamlessly once hydrated.
- **HTTP Transfer State Cache**: Caches server-side HTTP GET requests in the HTML payload, preventing the client browser from making duplicate API calls on startup.

```
Destructive Hydration (Legacy):
[Server HTML Painted] ──► [Client JS Boots] ──► [Wipes DOM & Re-creates Nodes! 💥 (Flicker)]

Non-Destructive Hydration with Event Replay (Modern):
[Server HTML Painted] ──► [User clicks button (Event recorded in queue)]
       │
       ▼ [Client JS Boots]
[Attaches listeners in-place (0 DOM destruction) ──► Replays recorded click! ✅]
```

---

## 2. Configuring SSR & Hydration (`app.config.ts`)

```typescript
// src/app/app.config.ts
import { type ApplicationConfig } from "@angular/core";
import { provideClientHydration, withEventReplay, withHttpTransferCacheOptions } from "@angular/platform-browser";
import { provideHttpClient, withFetch } from "@angular/common/http";

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(withFetch()),

    // Enable Non-Destructive Hydration with Event Replay & HTTP Transfer Cache:
    provideClientHydration(
      withEventReplay(), // Replays early user interactions
      withHttpTransferCacheOptions({
        includePostRequests: false, // Cache GET requests only
      })
    ),
  ],
};
```

---

## 3. The Server Entry Point (`app.config.server.ts` & `server.ts`)

```typescript
// src/app/app.config.server.ts
import { mergeApplicationConfig, type ApplicationConfig } from "@angular/core";
import { provideServerRendering } from "@angular/platform-server";
import { appConfig } from "./app.config";

const serverConfig: ApplicationConfig = {
  providers: [
    provideServerRendering(), // Enables Node.js server rendering engine
  ],
};

export const config = mergeApplicationConfig(appConfig, serverConfig);
```

```typescript
// server.ts (Express.js Server for Angular SSR)
import { APP_BASE_HREF } from "@angular/common";
import { CommonEngine } from "@angular/ssr";
import express from "express";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import bootstrap from "./src/main.server";

const server = express();
const serverDistFolder = dirname(fileURLToPath(import.meta.url));
const browserDistFolder = resolve(serverDistFolder, "../browser");
const indexHtml = join(serverDistFolder, "index.server.html");

const commonEngine = new CommonEngine();

// Serve static assets from browser output folder
server.get("*.*", express.static(browserDistFolder, { maxAge: "1y" }));

// All regular routes handled by Angular SSR engine
server.get("*", (req, res, next) => {
  const { protocol, originalUrl, baseUrl, headers } = req;

  commonEngine
    .render({
      bootstrap,
      documentFilePath: indexHtml,
      url: `${protocol}://${headers.host}${originalUrl}`,
      publicPath: browserDistFolder,
      providers: [{ provide: APP_BASE_HREF, useValue: baseUrl }],
    })
    .then((html) => res.send(html))
    .catch((err) => next(err));
});

const port = process.env["PORT"] || 4000;
server.listen(port, () => {
  console.log(`Node Express server listening on http://localhost:${port}`);
});
```

---

## 4. Guarding Platform-Specific APIs (`isPlatformBrowser` & `isPlatformServer`)

Executing browser-only APIs (`window`, `localStorage`, `document`) directly inside components will crash the Node.js SSR server with `ReferenceError`.

Use **`PLATFORM_ID`** to guard platform-specific logic:

```typescript
import { Component, inject, PLATFORM_ID, OnInit, signal } from "@angular/core";
import { isPlatformBrowser, isPlatformServer } from "@angular/common";

@Component({
  selector: "app-ssr-safe-widget",
  standalone: true,
  template: `
    <div>
      <p>Screen Width: {{ screenWidth() }}px</p>
    </div>
  `,
})
export class SsrSafeWidgetComponent implements OnInit {
  private platformId = inject(PLATFORM_ID);
  public screenWidth = signal<number>(1024); // Safe default for SSR

  ngOnInit(): void {
    if (isPlatformBrowser(this.platformId)) {
      // Safe to access window ONLY in browser environment:
      this.screenWidth.set(window.innerWidth);
      window.addEventListener("resize", () => {
        this.screenWidth.set(window.innerWidth);
      });
    }

    if (isPlatformServer(this.platformId)) {
      console.log("[SSR Render]: Rendering on Node.js Server");
    }
  }
}
```

---

## 5. Opting Out of Hydration with `ngSkipHydration`

If a third-party non-Angular widget (e.g. a Google Map or legacy jQuery plugin) directly manipulates the DOM before Angular hydrates, it will trigger hydration mismatch warnings.

You can explicitly skip hydration on that specific DOM node using **`ngSkipHydration`**:

```html
<!-- Skips hydration specifically on this widget node while hydrating the rest of the page normally: -->
<div class="third-party-widget" ngSkipHydration>
  <div id="google-maps-canvas"></div>
</div>
```

---

## Troubleshooting & Best Practices

1. **Hydration Node Mismatch Errors (`NG0500`)**
   `NG0500` occurs when the server-rendered HTML differs from the client's initial render tree (e.g. rendering `new Date().toLocaleTimeString()` or `Math.random()` directly in templates).
   *Fix:* Initialize with deterministic data, or compute dynamic client-only values inside `ngOnInit` guarded with `isPlatformBrowser()`.

2. **HTTP Transfer State Automatic Deduplication**
   With `withHttpTransferCacheOptions()` enabled in `provideClientHydration()`, any `HttpClient.get()` call executed on the server during SSR embeds its JSON response inside a `<script id="ng-state">` tag. When the client boots, it reads the data from that script tag with **zero duplicate network request!**
