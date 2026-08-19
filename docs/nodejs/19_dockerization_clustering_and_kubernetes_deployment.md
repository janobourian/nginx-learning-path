# Module 19: Production Dockerization, PID 1 Signals & Kubernetes Orchestration

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** DevOps Engineering, Docker Multi-Stage Builds & Kubernetes (K8s)

---

## 1. Enterprise Multi-Stage Dockerfile Engineering

A common anti-pattern is deploying Node.js development toolchains (TypeScript compiler, test runners, git) into production containers, resulting in bloated 1GB+ images filled with unpatched security vulnerabilities.

### The 4-Stage Multi-Stage Docker Build

```dockerfile

# ─── Stage 1: Base Image & Corepack ───
FROM node:20-alpine AS base
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate

# ─── Stage 2: Production Dependencies (Cached) ───
FROM base AS dependencies
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

# ─── Stage 3: Build & Compile TypeScript ───
FROM base AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build # Emits compiled JS to /app/dist

# ─── Stage 4: Hardened Production Runner ───
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

# Install dumb-init for proper PID 1 signal forwarding
RUN apk add --no-cache dumb-init

# Copy only production node_modules and compiled dist
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json

# CRITICAL SECURITY: Run as unprivileged non-root user 'node'
USER node

EXPOSE 3000

# Start via dumb-init to handle SIGTERM & zombie processes properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "dist/server.js"]
```

```bash

# Build and verify ultra-compact image
docker build -t enterprise-node-microservice:latest .
docker images enterprise-node-microservice:latest

# SIZE: ~95 MB (Ultra-fast pull & instant boot!)
```

---

## 2. Why Node.js Must NOT Run as PID 1 (The `dumb-init` Rule)

When a container starts, the primary process runs as **PID 1 (Process ID 1)** in the Linux kernel namespace.

In Linux, PID 1 has special responsibilities:

1. **Signal Handling**: Linux ignores `SIGTERM` and `SIGINT` signals for PID 1 unless the process explicitly registers handlers for them.
2. **Zombie Process Reaping**: When child processes or subprocesses exit, PID 1 is responsible for reaping orphan zombie processes from the OS process table.

Node.js is **not designed to be an init system**. If Node runs directly as PID 1:

- Kubernetes rolling updates will hang for 30 seconds before forcefully killing the container (`SIGKILL`), corrupting in-flight user requests!
- Zombie processes will slowly accumulate and exhaust kernel PID slots.

**Solution:** Always use a lightweight init supervisor like **`dumb-init`** or **`tini`** as the container `ENTRYPOINT`.

---

## 3. Production Healthcheck Endpoints (`/health/live` vs `/health/ready`)

Kubernetes requires two distinct health check probes:

```javascript
// src/health/health_probes.js
import http from 'node:http';
import { dbPool } from '../database/postgres_pool.js';
import { redis } from '../cache/redis_client.js';

export async function handleHealthProbes(req, res) {
  // 1. Liveness Probe (/health/live):
  // Checks if the Node.js event loop is responding (Not frozen in an infinite loop).
  if (req.url === '/health/live') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ALIVE', uptime: process.uptime() }));
    return true;
  }

  // 2. Readiness Probe (/health/ready):
  // Checks if the Pod can accept traffic (Database & Redis are connected).
  if (req.url === '/health/ready') {
    try {
      // Ping PostgreSQL:
      await dbPool.query('SELECT 1');

      // Ping Redis:
      await redis.ping();

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'READY', database: 'OK', redis: 'OK' }));
    } catch (err) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'UNHEALTHY', error: err.message }));
    }
    return true;
  }

  return false;
}
```

---

## 4. Production Kubernetes Deployment Manifest (`k8s/deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: enterprise-node-service
  namespace: production
  labels:
    app: enterprise-node-service
spec:
  replicas: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: enterprise-node-service
  template:
    metadata:
      labels:
        app: enterprise-node-service
    spec:
      terminationGracePeriodSeconds: 30 # Give 30s to drain active HTTP requests on SIGTERM
      containers:

        - name: node-app
          image: ghcr.io/acme/enterprise-node-service:v1.2.0
          imagePullPolicy: IfNotPresent
          ports:

            - containerPort: 3000
          env:

            - name: NODE_ENV
              value: "production"

            - name: PORT
              value: "3000"

            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database_url
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1024Mi" # Kills pod with OOMKilled if memory exceeds 1GB
          livenessProbe:
            httpGet:
              path: /health/live
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: enterprise-node-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: enterprise-node-service
  minReplicas: 3
  maxReplicas: 20
  metrics:

    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Production Deployment Checklist

- [ ] **Non-Root Execution**: Ensure `USER node` is set in the production Docker runner stage.
- [ ] **PID 1 Signal Supervisor**: Wrap the Node executable in `dumb-init` or `tini`.
- [ ] **Dual Health Probes**: Configure both `/health/live` and `/health/ready` in Kubernetes manifests.
- [ ] **Explicit Resource Limits**: Always declare `requests` and `limits` for CPU and Memory in Kubernetes.
- [ ] **Graceful Drain Handling**: Intercept `SIGTERM` in your Node server to stop accepting new requests, close database pools, and allow in-flight HTTP requests up to 25s to finish before exiting.
