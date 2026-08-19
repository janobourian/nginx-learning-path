# Module 19: Enterprise Containerization, Multi-Stage Docker & Kubernetes Orchestration

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** DevOps Engineering, Container Security & Kubernetes Orchestration

---

## 1. Multi-Stage Docker Build for Modern JavaScript Runtimes

```dockerfile

# ─── Stage 1: Dependency Builder ───
FROM node:20-alpine AS deps
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

# ─── Stage 2: TypeScript Compiler ───
FROM node:20-alpine AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# ─── Stage 3: Hardened Production Runner ───
FROM gcr.io/distroless/nodejs20-debian12:nonroot AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

# Copy production artifacts from builder stages
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json

# Distroless runs automatically as unprivileged non-root user (nonroot:nonroot)
EXPOSE 8080
CMD ["dist/main.js"]
```

---

## 2. Graceful Shutdown & Signal Trapping (`SIGTERM` / `SIGINT`)

When Kubernetes scales down or rolls out a new deployment, it sends a **`SIGTERM`** signal to the pod.

If the application terminates abruptly, active user HTTP requests, payments, and database transactions will be aborted.

### Enterprise Graceful Shutdown Implementation

```javascript
// src/lifecycle/graceful_shutdown.js
import process from 'node:process';

export function setupGracefulShutdown(httpServer, dbPool, redisClient) {
  let isShuttingDown = false;

  async function handleSignal(signal) {
    if (isShuttingDown) return;
    isShuttingDown = true;

    console.log(`\n[Shutdown]: Received ${signal}. Initiating graceful drainage...`);

    // 1. Stop accepting new incoming HTTP connections:
    httpServer.close(async () => {
      console.log('[Shutdown]: HTTP server closed.');

      try {
        // 2. Drain and close Database Pool:
        console.log('[Shutdown]: Closing Database connection pool...');
        await dbPool.end();

        // 3. Disconnect Redis Client:
        console.log('[Shutdown]: Disconnecting Redis...');
        await redisClient.quit();

        console.log('[Shutdown]: All connections drained cleanly. Exiting with code 0.');
        process.exit(0);
      } catch (err) {
        console.error('[Shutdown Error]: Error during resource cleanup:', err);
        process.exit(1);
      }
    });

    // 4. Force exit if cleanup takes longer than 25 seconds (Safety Timeout):
    setTimeout(() => {
      console.error('[Shutdown]: Graceful drain timeout exceeded. Force terminating.');
      process.exit(1);
    }, 25000).unref();
  }

  process.on('SIGTERM', () => handleSignal('SIGTERM'));
  process.on('SIGINT', () => handleSignal('SIGINT'));
}
```

---

## 3. Production Kubernetes Deployment Manifest (`k8s/deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: enterprise-backend-service
  namespace: production
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: enterprise-backend-service
  template:
    metadata:
      labels:
        app: enterprise-backend-service
    spec:
      terminationGracePeriodSeconds: 30 # Give 30s for graceful shutdown
      containers:

        - name: backend-service
          image: ghcr.io/acme/enterprise-backend:v2.1.0
          imagePullPolicy: IfNotPresent
          ports:

            - containerPort: 8080
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "2000m"
              memory: "2048Mi"
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
```

---

## Enterprise Production Deployment Checklist

- [ ] **Distroless Base Images**: Deploy using `gcr.io/distroless/nodejs20-debian12:nonroot` to guarantee zero OS shell or package manager vulnerabilities.
- [ ] **Graceful Signal Handling**: Always intercept `SIGTERM` and allow up to 25s for in-flight transactions to drain before closing.
- [ ] **Dual Health Probes**: Implement `/health/live` (event loop check) and `/health/ready` (database/cache connectivity check) in Kubernetes.
- [ ] **Explicit Resource Limits**: Configure memory and CPU requests/limits to prevent runaway OOM container restarts.
- [ ] **Structured Telemetry**: Ship JSON logs with Correlation IDs and OpenTelemetry traces to your central observability platform.
