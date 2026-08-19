# Module 18: CI/CD — GitHub Actions, Docker & Deployment Pipelines

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Continuous Integration & Delivery

---

## CI/CD for Deno Applications

Deno's built-in toolchain makes CI pipelines simple: no separate build tool installations, no package manager setup beyond caching the Deno binary itself. A complete CI check — format, lint, type-check, test — runs with four commands.

---

## GitHub Actions: Basic CI Pipeline

```yaml

# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  ci:
    name: Test & Lint
    runs-on: ubuntu-latest

    steps:

      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Deno
        uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x   # Always use latest 2.x

      # Cache the Deno module cache to speed up runs
      - name: Cache Deno modules
        uses: actions/cache@v4
        with:
          path: ~/.cache/deno
          key: deno-${{ runner.os }}-${{ hashFiles('deno.lock') }}
          restore-keys: |
            deno-${{ runner.os }}-

      - name: Check formatting
        run: deno fmt --check

      - name: Lint
        run: deno lint

      - name: Type check
        run: deno check src/main.ts

      - name: Run tests
        run: deno test --allow-net=localhost --allow-read=./fixtures --allow-env=TEST_DATABASE_URL
        env:
          TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}

      - name: Generate coverage report
        run: |
          deno test --coverage=coverage_data --allow-net=localhost --allow-read=./fixtures
          deno coverage coverage_data --lcov --output=coverage.lcov

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: coverage.lcov
          token: ${{ secrets.CODECOV_TOKEN }}
```

---

## Docker: Minimal Deno Image

```dockerfile

# Dockerfile

# Stage 1: Cache dependencies (this layer is only rebuilt when deno.lock changes)
FROM denoland/deno:2.1.4 AS deps

WORKDIR /app
COPY deno.json deno.lock ./
COPY src/ ./src/

# Pre-download and compile all dependencies
RUN deno cache src/main.ts

# Stage 2: Production image
FROM denoland/deno:2.1.4

# Run as non-root user for security
USER deno
WORKDIR /app

# Copy cached modules from deps stage
COPY --from=deps /root/.cache /root/.cache
COPY --from=deps /app /app

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["run", \
     "--allow-net=0.0.0.0:8080", \
     "--allow-env=PORT,DATABASE_URL,REDIS_URL,API_SECRET", \
     "--allow-read=./public", \
     "src/main.ts"]
```

```yaml

# docker-compose.yml — local development with dependencies
version: "3.9"

services:
  api:
    build: .
    ports:

      - "8080:8080"
    environment:
      PORT: "8080"
      DATABASE_URL: "postgres://user:pass@postgres:5432/myapp"
      REDIS_URL: "redis://redis:6379"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:

      - ./public:/app/public:ro  # Mount public assets read-only

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: myapp
    volumes:

      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d myapp"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

---

## Deploy to Deno Deploy via CI

```yaml

# .github/workflows/deploy.yml
name: Deploy to Deno Deploy

on:
  push:
    branches: [main]

jobs:
  test:
    uses: ./.github/workflows/ci.yml   # Reuse the CI workflow

  deploy:
    name: Deploy to Production
    needs: test
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:

      - uses: actions/checkout@v4
      - uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x

      - name: Deploy to Deno Deploy
        uses: denoland/deployctl@v1
        with:
          project: my-api
          entrypoint: src/main.ts
          # Automatically uses OIDC for authentication (no token needed)
```

---

## Deploy to a VPS with Docker

```yaml

# .github/workflows/deploy-vps.yml
name: Deploy to VPS

on:
  push:
    branches: [main]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:

      - uses: actions/checkout@v4

      - name: Login to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    environment: production

    steps:

      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            # Pull the new image
            docker pull ghcr.io/${{ github.repository }}:${{ github.sha }}

            # Zero-downtime update: start new, verify, stop old
            docker run -d \
              --name api-new \
              --network app-network \
              -e DATABASE_URL="${{ secrets.DATABASE_URL }}" \
              -e API_SECRET="${{ secrets.API_SECRET }}" \
              ghcr.io/${{ github.repository }}:${{ github.sha }}

            # Health check the new container
            sleep 5
            if docker exec api-new curl -sf http://localhost:8080/health; then
              docker stop api-current || true
              docker rename api-current api-old || true
              docker rename api-new api-current
              docker rm api-old || true
              echo "Deployment successful"
            else
              docker stop api-new && docker rm api-new
              echo "Deployment failed — rolling back"
              exit 1
            fi
```

---

## Integration Tests in CI

```typescript
// tests/integration/api_test.ts
import { assertEquals, assertExists } from "@std/assert";

const BASE_URL = Deno.env.get("API_URL") ?? "http://localhost:8080";

// Start the server for integration testing
let server: ReturnType<typeof Deno.serve>;

// Setup: start the server before tests run
// (If using a real test server, import and start the app here)

Deno.test({
  name: "POST /api/users creates user",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const response = await fetch(`${BASE_URL}/api/users`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "Test User",
        email: `test-${crypto.randomUUID()}@example.com`,
        password: "SecureP@ss1",
      }),
    });

    assertEquals(response.status, 201);
    const user = await response.json();
    assertExists(user.id);
    assertEquals(user.name, "Test User");
  },
});

Deno.test({
  name: "GET /health returns 200",
  async fn() {
    const response = await fetch(`${BASE_URL}/health`);
    assertEquals(response.status, 200);
    const data = await response.json();
    assertEquals(data.status, "ok");
  },
});
```

Run integration tests pointing at the live staging environment:

```bash
API_URL=https://staging.example.com deno test \
  --allow-net=staging.example.com \
  --allow-env=API_URL \
  tests/integration/
```

---

## `deno.json` Complete CI Task Setup

```json
{
  "tasks": {
    "dev": "deno run --watch --allow-net --allow-env --allow-read src/main.ts",
    "start": "deno run --allow-net --allow-env --allow-read src/main.ts",
    "test": "deno test --allow-net=localhost:5432 --allow-read=./fixtures --allow-env",
    "test:cov": "deno test --coverage=.cov --allow-net=localhost:5432 --allow-read=./fixtures --allow-env && deno coverage .cov",
    "test:int": "deno test --allow-net --allow-env tests/integration/",
    "check": "deno check src/main.ts",
    "fmt": "deno fmt",
    "fmt:check": "deno fmt --check",
    "lint": "deno lint",
    "ci": "deno fmt --check && deno lint && deno check src/main.ts && deno test",
    "build": "deno compile --allow-net --allow-env --output dist/server src/main.ts"
  }
}
```

---

## Troubleshooting

### CI fails with `deno: command not found`

Use `denoland/setup-deno@v2` action before any `run: deno ...` step. This installs Deno into the GitHub Actions runner PATH.

### Module cache miss every CI run (slow downloads)

Ensure the cache key includes `deno.lock`: `key: deno-${{ runner.os }}-${{ hashFiles('deno.lock') }}`. Also ensure the cache path matches the Deno install's actual cache location. Run `deno info` in CI to see the cache path.

### Docker image fails HEALTHCHECK during deployment

The health endpoint `/health` may not be available during container startup (before the HTTP server starts listening). Use `--start-period=10s` in HEALTHCHECK to give the server time to boot. Also ensure `--allow-net` includes the health check's listen address.
