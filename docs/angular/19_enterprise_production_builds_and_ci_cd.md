# Module 19: Enterprise Production Builds, Docker & CI/CD Pipelines

**Track:** Angular — Signals Platform & Ivy Architecture  
**Category:** DevOps, Build Optimization & Enterprise Production Deployment

---

## 1. The Modern Angular Application Builder (`@angular-devkit/build-angular:application`)

In Angular 17+, the legacy Webpack build pipeline is replaced by the unified **`application` builder**:
- Powered by **esbuild** for ultra-fast bundling and tree-shaking.
- Powered by **Vite** for local development server and Hot Module Replacement (HMR).
- Simultaneously generates the **Browser Client Bundle**, **Server SSR Node Bundle**, and **Prerendered HTML files** in a single execution pass!

```bash
# Execute production optimized build:
ng build --configuration production
```

---

## 2. Bundle Budgets in `angular.json`

Enterprise repositories enforce **Bundle Budgets** in `angular.json` to automatically fail CI/CD pull requests if a new npm dependency bloats the application bundle:

```json
// angular.json
"configurations": {
  "production": {
    "budgets": [
      {
        "type": "initial",
        "maximumWarning": "500kB",
        "maximumError": "1MB"
      },
      {
        "type": "anyComponentStyle",
        "maximumWarning": "4kB",
        "maximumError": "8kB"
      }
    ],
    "outputHashing": "all",
    "sourceMap": false,
    "optimization": true
  }
}
```

---

## 3. Multi-Stage Production Dockerfile (SPA with NGINX)

For pure client-side SPA Angular applications, this multi-stage Docker build produces a hardened, sub-30MB container served by NGINX:

```dockerfile
# ─── Stage 1: Build Angular Application ───
FROM node:20-alpine AS builder
WORKDIR /app

# Install pnpm & dependencies
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy application source and build production bundle
COPY . .
RUN pnpm run build --configuration=production

# ─── Stage 2: Hardened NGINX Runtime ───
FROM nginx:alpine-slim AS runner

# Remove default NGINX website
RUN rm -rf /usr/share/nginx/html/*

# Copy custom NGINX configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy compiled Angular browser assets
COPY --from=builder /app/dist/my-angular-app/browser /usr/share/nginx/html

# Expose HTTP port
EXPOSE 80

# Run NGINX in foreground
CMD ["nginx", "-g", "daemon off;"]
```

---

## 4. Production NGINX Configuration for Angular (`nginx.conf`)

Angular uses HTML5 PushState routing. If a user directly visits `/dashboard/projects` or refreshes the browser, NGINX must fallback to `index.html`:

```nginx
# nginx.conf
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;" always;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/x-javascript application/json application/xml;

    # 1. Static Hashed Chunks: Cache for 1 Year (Immutable)
    location ~* \.(?:js|css|woff2|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # 2. HTML5 PushState Routing Fallback:
    location / {
        try_files $uri $uri/ /index.html =404;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # 3. Healthcheck Probe for Kubernetes
    location = /healthz {
        access_log off;
        return 200 "healthy\n";
    }
}
```

---

## 5. Enterprise GitHub Actions CI/CD Pipeline (`.github/workflows/ci.yml`)

```yaml
name: Enterprise Angular CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v4

      - name: Setup Node.js 20
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: "npm"

      - name: Install Dependencies
        run: npm ci

      - name: Run ESLint & Angular Template Checks
        run: npm run lint

      - name: Run TypeScript Typecheck
        run: npx tsc --noEmit

      - name: Run Unit Tests (Headless Chrome)
        run: npm run test -- --no-watch --no-progress --browsers=ChromeHeadless

      - name: Compile Production Build & Verify Budgets
        run: npm run build -- --configuration=production

  build-and-push-docker:
    needs: validate-and-test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and Push Production Container
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}/angular-app:latest,ghcr.io/${{ github.repository }}/angular-app:${{ github.sha }}
```

---

## Enterprise Production Deployment Checklist

- [ ] **Zoneless / OnPush Verification**: Ensure components use `OnPush` change detection to maximize frame rates.
- [ ] **Bundle Budget Enforcement**: Configure strict initial and component style budgets in `angular.json`.
- [ ] **NGINX PushState Routing**: Verify `try_files $uri $uri/ /index.html` is configured to prevent 404s on browser refresh.
- [ ] **Security Headers**: Inject CSP, HSTS, and X-Content-Type-Options headers in production web servers.
- [ ] **Image & Font Optimization**: Preconnect to font domains and serve WebP/AVIF assets with long-term immutable caching headers.
