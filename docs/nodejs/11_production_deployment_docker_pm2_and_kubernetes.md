# Module 11: Production Deployment: Docker Multi-Stage, PM2 & Kubernetes

**Track:** Node.js Enterprise Backend & Runtime  
**Directory:** `docs/nodejs/`  
**File:** `11_production_deployment_docker_pm2_and_kubernetes.md`  
**Category:** Cloud Deployment, Containerization & Kubernetes Orchestration  
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. High-Level Overview & Architectural Foundations

Deploying Node.js applications into enterprise production environments requires strict adherence to containerization best practices, automated process supervision, and zero-downtime orchestration. Running Node.js directly via `npm start` in production introduces severe operational hazards: `npm` swallows POSIX `SIGTERM` signals, blocking graceful teardown and causing dropped client connections during rolling updates.

Enterprise production deployments rely on three foundational pillars:
1. **Multi-Stage Distroless / Alpine Docker Builds**: Strips TypeScript compilers, linters, development dependencies, and root shell utilities, shrinking container image sizes from 1.2GB down to $< 120\text{MB}$ and minimizing security attack surfaces.
2. **Non-Root Execution (`USER node`)**: Prevents container breakout vulnerabilities by running application processes under an unprivileged UID.
3. **Kubernetes Health Probes & Graceful Pod Lifecycle**: Configures Startup, Liveness, and Readiness probes alongside a 30-second `terminationGracePeriodSeconds` to ensure zero dropped requests during rolling cluster updates.

```
+-------------------------------------------------------------------------------+
|                       Production Container Build Pipeline                     |
+-------------------------------------------------------------------------------+

  [ Stage 1: Build & Compile (node:20-alpine) ]
    - Installs devDependencies & TypeScript compiler
    - Compiles src/ to dist/ with strict types
    - Runs automated unit tests and schema checks
                         |
                         v  (Copies only dist/ and production node_modules)
  [ Stage 2: Production Distroless / Minimal Alpine Image ]
    - Base: node:20-alpine (or gcr.io/distroless/nodejs20-debian12)
    - Sets USER node (UID 1000)
    - Zero package managers or build compilers
    - Final Image Size: 110 MB (vs 1.2 GB raw build)
```

---

## 2. Complete Container & Orchestration Configuration Dictionary

Below is the complete configuration dictionary for Docker, PM2, and Kubernetes:

| Directive / Key | Environment | Format / Syntax | Operational Execution Semantics |
| :--- | :--- | :--- | :--- |
| `COPY --from=builder` | Docker | `COPY --from=builder /app/dist ./dist` | Multi-stage build step copying compiled artifacts from the builder image. |
| `USER node` | Docker | `USER node` | Switches container execution user from `root` to the unprivileged `node` user. |
| `ENTRYPOINT ["node"]` | Docker | `ENTRYPOINT ["node", "dist/server.js"]` | Executes Node.js directly as PID 1, ensuring POSIX signals (`SIGTERM`) are delivered cleanly. |
| `instances: 'max'` | PM2 | `instances: 'max', exec_mode: 'cluster'`| Spawns one worker process per logical CPU core in cluster mode. |
| `max_memory_restart` | PM2 | `max_memory_restart: '500M'` | Automatically reboots worker process if V8 memory exceeds 500MB, preventing OOM crashes. |
| `wait_ready: true` | PM2 | `wait_ready: true, listen_timeout: 10000`| Waits for worker process to send `process.send('ready')` before routing traffic. |
| `startupProbe` | Kubernetes | `startupProbe: { httpGet: { path: '/health/live' } }`| Polls pod startup; disables liveness/readiness checks until startup succeeds (prevents premature kill). |
| `livenessProbe` | Kubernetes | `livenessProbe: { failureThreshold: 3 }` | Detects deadlocks and restarts unresponsive containers. |
| `readinessProbe` | Kubernetes | `readinessProbe: { httpGet: { path: '/health/ready' } }`| Signals load balancer to route traffic only when service is fully initialized and warmed up. |
| `terminationGracePeriodSeconds`| Kubernetes | `terminationGracePeriodSeconds: 30` | Time allocated for in-flight requests to drain after `SIGTERM` before sending `SIGKILL`. |

---

## 3. Technical Deep Dive: PID 1 Signal Forwarding & Container Termination

When a Docker container starts with `CMD npm start` or `CMD ["sh", "-c", "node app.js"]`:
* The **Shell (`/bin/sh`) or `npm` becomes Process ID 1 (PID 1)**.
* When Kubernetes sends a `SIGTERM` to terminate the pod, the shell does **not forward** the signal to the child Node.js process.
* The Node.js application continues executing unaware that termination is imminent.
* After 30 seconds, Kubernetes sends `SIGKILL (signal 9)`, instantly terminating the container and aborting all in-flight HTTP connections and database transactions.

### The Fix: Direct Node.js Execution (`ENTRYPOINT ["node", "dist/server.js"]`)
By executing `node` directly as PID 1 (or using a minimal init system like `tini`), Node.js receives `SIGTERM` instantly and initiates graceful teardown.

---

## 4. Hands-On Step-by-Step Production Lab: Multi-Stage Dockerfile & Kubernetes Manifests

### File 1: `Dockerfile`
```dockerfile
# ===================================================
# STAGE 1: Build & Compilation Stage
# ===================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Install build dependencies
COPY package*.json tsconfig.json ./
RUN npm ci

# Copy application source and compile
COPY src/ ./src/
RUN npx tsc --project tsconfig.json

# Prune development dependencies to keep only production packages
RUN npm prune --production

# ===================================================
# STAGE 2: Minimal Distroless Production Runtime
# ===================================================
FROM node:20-alpine AS production

# Set production environment
ENV NODE_ENV=production
ENV PORT=8080

WORKDIR /app

# Copy production artifacts from builder
COPY --from=builder --chown=node:node /app/package*.json ./
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/dist ./dist

# Run as unprivileged node user (UID 1000)
USER node

# Expose service port
EXPOSE 8080

# Direct execution as PID 1 for proper signal propagation
ENTRYPOINT ["node", "--max-old-space-size=384", "--enable-source-maps", "dist/server.js"]
```

### File 2: `k8s/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: enterprise-node-service
  namespace: production
  labels:
    app: enterprise-node-service
spec:
  replicas: 4
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  selector:
    matchLabels:
      app: enterprise-node-service
  template:
    metadata:
      labels:
        app: enterprise-node-service
    spec:
      terminationGracePeriodSeconds: 35
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - enterprise-node-service
                topologyKey: topology.kubernetes.io/zone
      containers:
        - name: node-service
          image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/enterprise-node-service:v1.0.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: NODE_ENV
              value: "production"
            - name: PORT
              value: "8080"
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "768Mi"
          startupProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 2
            periodSeconds: 2
            failureThreshold: 15
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
```

---

## 5. Pure Escaped CLI Snippets (Production Operations)

```bash
# 1. Build optimized multi-stage Docker image
docker build \
    --target production \
    -t enterprise-node-service:v1.0.0 \
    .

# 2. Run container locally with security sandboxing and memory caps
docker run -d \
    --name node-app \
    --read-only \
    --cap-drop=ALL \
    --memory=512m \
    --cpus=1.0 \
    -p 8080:8080 \
    enterprise-node-service:v1.0.0

# 3. Test rolling update in Kubernetes cluster with zero downtime
kubectl rollout restart deployment/enterprise-node-service -n production \
    && kubectl rollout status deployment/enterprise-node-service -n production
```

---

## 6. Detailed Sub-Components & Diagnostics

### Linux Kernel Cgroups v2 Memory Controller
* **Role & Function**: Enforces hard container memory ceilings (`memory.max`), triggering Linux OOM killer if container exceeds limits.
* **Inspection Command**:
  ```bash
  cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max
  ```

### Kubernetes Kubelet Probe Manager
* **Role & Function**: Executes periodic HTTP GET requests against `/health/live` and `/health/ready`, updating endpoints in Kubernetes Endpoints controller.
* **Inspection Command**:
  ```bash
  kubectl describe pod -l app=enterprise-node-service -n production
  ```

---

## References

### Official Documentation
* [Docker Multi-Stage Builds Documentation](https://docs.docker.com/build/building/multi-stage/) — Container optimization.
* [Kubernetes Container Lifecycle Hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/) — Pod lifecycle management.
* [Kubernetes Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) — Health checks.
* [PM2 Production Process Manager Reference](https://pm2.keymetrics.io/docs/usage/quick-start/) — Node.js process clustering.
* [Open Container Initiative (OCI) Image Specification](https://opencontainers.org/) — Container standards.

### Authoritative Engineering Blogs
* [Brendan Gregg: Container Performance and Resource Sizing](https://www.brendangregg.com/) — Cgroups analysis.
* [Netflix TechBlog: Zero-Downtime Rolling Deployments](https://netflixtechblog.com/) — Pod draining patterns.
* [Matteo Collina: Node.js in Docker Done Right](https://noders.com/) — Signal propagation.
* [Cloudflare Engineering: Ultra-Fast Container Startup](https://blog.cloudflare.com/) — Cold start optimization.
* [Google Cloud Architecture Center: Best Practices for Building Containers](https://cloud.google.com/architecture/best-practices-for-building-containers) — Container security.

---

## 7. FinOps & Cloud Resource Cost Governance

*Multi-stage builds shrink container images by 90%, speeding up pod autoscaling cold-starts and cutting ECR bandwidth costs.*

### 1. 90% Reduction in Container Image Size
Shrinking container images from 1.2GB down to 110MB cuts image download times across AWS ECR and Kubernetes nodes from 25 seconds down to **1.5 seconds**. During sudden traffic spikes, new pods transition from `Pending` to `Running` in under 3 seconds, handling incoming load before requests timeout.

### 2. Eliminating Memory Over-Provisioning via Distroless Base
Eliminating unnecessary OS binaries (package managers, compilers, curl, bash) cuts base idle container RAM consumption from 180MB down to $< 35\text{MB}$, allowing a 16GB RAM cloud node to host 40 pods instead of 18.

---

## 8. Troubleshooting, Diagnostic Workflows & Common Anti-Patterns

### Common Anti-Patterns

1. **Running Containers as `root`**:
   - *Anti-Pattern*: Omitting `USER node` in the Dockerfile. If an attacker exploits a remote code execution vulnerability, they gain root access inside the container and can attempt kernel privilege escalation.
   - *Fix*: Always declare `USER node` before the `ENTRYPOINT` directive.

2. **Using `npm start` as the Container Entrypoint**:
   - *Anti-Pattern*: Declaring `CMD ["npm", "start"]`. `npm` ignores `SIGTERM`, preventing graceful connection draining during Kubernetes pod rotation.
   - *Fix*: Always declare `ENTRYPOINT ["node", "dist/server.js"]`.

3. **Setting Resource Limits Equal to Requests on CPU**:
   - *Anti-Pattern*: Setting `cpu.limits: 250m` equal to `cpu.requests: 250m`. The Linux CFS scheduler throttles CPU execution when bursts occur, causing latency spikes.
   - *Fix*: Set `cpu.requests: 250m` and allow generous bursting (`cpu.limits: 1000m` or omit CPU limits while keeping memory limits strict).
