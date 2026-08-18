# Module 19: Production Deployment & Dockerization

**Track:** Vue — Progressive Web Framework  
**Category:** DevOps, Security & Production Engineering

---

## Production Readiness Checklist

Before shipping a Vue 3 Single Page Application (SPA) or Nuxt 3 Universal SSR app to production, verify the following:

- [ ] **Type Checking Gate**: `vue-tsc --noEmit` passes with zero errors in CI.
- [ ] **Bundle Analysis**: No duplicate packages or oversized dependencies (>500KB chunk warning).
- [ ] **Asset Caching**: Hashed static assets (`assets/*.js`) have `Cache-Control: public, max-age=31536000, immutable`.
- [ ] **Entry HTML Caching**: `index.html` has `Cache-Control: no-cache, no-store, must-revalidate`.
- [ ] **Security Headers**: HSTS, Content-Security-Policy (CSP), X-Frame-Options, X-Content-Type-Options.
- [ ] **Error Tracking & Telemetry**: Sentry / Datadog Vue integration initialized.
- [ ] **Container Security**: Docker images run as non-root users (`USER node` / `USER nginx`).

---

## 1. Multi-Stage Dockerfile for Vue 3 SPA + NGINX

For client-side Single Page Applications, the build output is static HTML, CSS, and JS. Use a multi-stage Docker build that compiles with Node.js and serves with a hardened Alpine NGINX image:

```dockerfile
# Stage 1: Build static assets
FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency manifests first for optimal layer caching
COPY package*.json ./
RUN npm ci

# Copy source code and build
COPY . .
RUN npm run build

# Stage 2: Production NGINX server
FROM nginx:1.27-alpine AS production

# Remove default NGINX configuration
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom hardened NGINX configuration
COPY nginx.conf /etc/nginx/conf.d/app.conf

# Copy compiled static assets from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Expose HTTP port
EXPOSE 80

# Health check probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

---

## 2. Hardened NGINX Production Configuration (`nginx.conf`)

This configuration handles Vue Router HTML5 History mode (`try_files`), Gzip compression, asset caching headers, and security hardening:

```nginx
# /etc/nginx/conf.d/app.conf
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https:; connect-src 'self' https://api.example.com;" always;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/x-javascript application/json application/xml image/svg+xml;
    gzip_disable "MSIE [1-6]\.";

    # Static Assets with Hash: Cache for 1 Year
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # Favicon and Robots
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    location = /robots.txt {
        log_not_found off;
        access_log off;
    }

    # Vue Router HTML5 History Mode Fallback
    # If file ($uri) or directory ($uri/) does not exist, serve index.html
    location / {
        try_files $uri $uri/ /index.html;
        # Never cache index.html so users get instant updates on deployment
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # Deny access to hidden files (.git, .env, etc.)
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
```

---

## 3. Multi-Stage Dockerfile for Nuxt 3 Universal SSR

For server-rendered Nuxt applications, deploy the lightweight Nitro Node server:

```dockerfile
# Stage 1: Build the Nuxt application
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Stage 2: Production runtime (Ultra-minimal Node image)
FROM node:20-alpine AS production

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

# Copy compiled Nitro server output (.output directory)
COPY --from=builder /app/.output /app/.output

# Run as non-root unprivileged node user
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1

# Start the standalone Nitro server
CMD ["node", ".output/server/index.mjs"]
```

---

## 4. Vite Bundle Optimization & Code Splitting

Configure `vite.config.ts` to inspect and partition large vendor dependencies:

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { visualizer } from "rollup-plugin-visualizer";

export default defineConfig({
  plugins: [
    vue(),
    // Generates stats.html showing interactive bundle size map
    visualizer({
      filename: "./dist/stats.html",
      open: false,
      gzipSize: true,
      brotliSize: true,
    }),
  ],
  build: {
    target: "es2022",
    minify: "terser",
    terserOptions: {
      compress: {
        drop_console: true, // Strip console.log in production
        drop_debugger: true,
      },
    },
    rollupOptions: {
      output: {
        // Chunk splitting for optimal long-term browser caching
        manualChunks(id) {
          if (id.includes("node_modules")) {
            if (id.includes("vue") || id.includes("pinia") || id.includes("vue-router")) {
              return "vue-core";
            }
            if (id.includes("lodash") || id.includes("date-fns") || id.includes("zod")) {
              return "utils";
            }
            return "vendor";
          }
        },
      },
    },
  },
});
```

---

## 5. GitHub Actions Production CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Build & Deploy Production

on:
  push:
    branches: [main]

jobs:
  ci-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Lint & Format Check
        run: npm run lint

      - name: Type Check
        run: npm run type-check

      - name: Unit & Integration Tests
        run: npm run test -- --coverage

  build-and-push-docker:
    needs: ci-test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push container image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## Troubleshooting Production Deployments

1. **404 Not Found on Page Refresh in Vue Router SPA**
   This occurs when NGINX attempts to find a literal file corresponding to the route path (e.g. `/users/123/profile`) on disk. Ensure `try_files $uri $uri/ /index.html;` is present in your NGINX configuration so all non-asset requests fall back to `index.html`.

2. **Hydration Mismatch in Nuxt 3 SSR**
   Check for date parsing difference, browser-specific variables accessed during setup, or extensions injecting elements into the DOM. Use `<ClientOnly>` component wrapper around client-only widgets.

3. **CORS Errors in Production**
   Ensure your backend API sends appropriate `Access-Control-Allow-Origin` headers matching your production domain, or route all API requests through the NGINX reverse proxy (`location /api/ { proxy_pass http://backend:8080; }`).
