# Module 19: Standalone Docker Deployment, Kubernetes & Self-Hosting

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** DevOps, Docker Containerization & Cloud Deployment

---

## 1. Next.js Standalone Mode (`output: "standalone"`)

By default, deploying a full-stack Next.js application required copying the entire `node_modules` directory (often 500MB – 1.5GB) into production containers.

Next.js includes **Standalone Output Mode** (`output: "standalone"`).

When you build with standalone mode enabled:
1. Next.js analyzes your entire application using `@vercel/nft` (Node File Trace).
2. It traces only the specific files, modules, and npm packages actually used by your code.
3. It bundles a self-contained, minimal Node.js server inside `.next/standalone/` that **weighs only ~60MB–90MB** and runs without needing a global `node_modules` folder!

```typescript
// next.config.ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone", // Enables standalone minimal server output
};

export default nextConfig;
```

---

## 2. Multi-Stage Production Dockerfile

This multi-stage Docker build produces a hardened, non-root, sub-100MB production image:

```dockerfile
# ─── Stage 1: Base Dependencies ───
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy dependency manifests
COPY package.json package-lock.json* ./
RUN npm ci

# ─── Stage 2: Builder ───
FROM node:20-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set production environment flags
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Compile Next.js application
RUN npm run build

# ─── Stage 3: Production Runner (Minimal & Hardened) ───
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Create unprivileged non-root system user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy static assets and standalone server output
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Switch to non-root user
USER nextjs

EXPOSE 3000

# Container Healthcheck Probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1

# Start the standalone server directly with node
CMD ["node", "server.js"]
```

---

## 3. Production Healthcheck Endpoint (`/api/health`)

```typescript
// src/app/api/health/route.ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    // 1. Verify Database connectivity:
    await db.$queryRaw`SELECT 1`;

    return NextResponse.json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      memoryUsageMb: Math.round(process.memoryUsage().rss / 1024 / 1024),
    });
  } catch (error) {
    return NextResponse.json(
      {
        status: "unhealthy",
        error: (error as Error).message,
      },
      { status: 503 }
    );
  }
}
```

---

## 4. Production NGINX Reverse Proxy Configuration

When hosting Next.js on your own VPS or Kubernetes cluster, place **NGINX** in front of Next.js to handle SSL termination, Gzip/Brotli compression, rate limiting, and caching of static assets:

```nginx
# /etc/nginx/conf.d/nextjs.conf
upstream nextjs_upstream {
    server 127.0.0.1:3000;
    keepalive 64;
}

server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    # 1. Hashed Static Assets: Cache indefinitely (1 year)
    location /_next/static/ {
        proxy_pass http://nextjs_upstream;
        proxy_cache_valid 200 365d;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # 2. Public Static Files
    location /public/ {
        proxy_pass http://nextjs_upstream;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    # 3. Dynamic Server Components & API Traffic
    location / {
        proxy_pass http://nextjs_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # Disable buffering for real-time SSE & LLM chunk streaming:
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
```

---

## 5. Kubernetes Deployment Manifest (`deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextjs-app
  labels:
    app: nextjs-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nextjs-app
  template:
    metadata:
      labels:
        app: nextjs-app
    spec:
      containers:
        - name: nextjs
          image: ghcr.io/my-org/nextjs-app:latest
          ports:
            - containerPort: 3000
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: database-url
            - name: AUTH_SECRET
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: auth-secret
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1024Mi"
          livenessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
```

---

## Production Deployment Checklist

- [ ] **Standalone Output**: Ensure `output: "standalone"` is configured in `next.config.ts`.
- [ ] **Non-Root User**: Verify Docker container runs under `USER nextjs` (UID 1001).
- [ ] **Streaming Proxy Buffering**: Ensure `proxy_buffering off;` is set in NGINX so Server-Sent Events (SSE) and AI completion streams work without buffering.
- [ ] **Healthcheck Endpoint**: Implement `/api/health` with database ping check for Kubernetes probes.
- [ ] **Automated Revalidation Secrets**: Secure on-demand revalidation webhooks with cryptographically signed tokens.
