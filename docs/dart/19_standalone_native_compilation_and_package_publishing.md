# Module 19: Standalone Native Compilation, Distroless Docker & Package Publishing

**Track:** Dart — Language & VM Architecture  
**Category:** DevOps, Native AOT Deployment & Package Registry Publishing

---

## 1. Standalone Native AOT Compilation (`dart compile exe`)

Dart can compile full-stack backend servers and command-line utilities into **self-contained native machine code executables**:
- Requires **zero Dart SDK or VM installed** on the production host or container!
- Cold-start execution in **< 10 milliseconds**.
- Minimal heap memory usage (often under 20MB baseline).

```bash
# Compile to self-contained native binary:
dart compile exe bin/server.dart -o build/server_app

# Verify binary execution directly:
./build/server_app
```

---

## 2. Ultra-Minimal Sub-20MB Distroless Dockerfile

By combining Dart's native AOT compilation with Google's **Distroless Linux Base Image** (which contains only minimal glibc runtime libraries with zero shell, zero package manager, and zero attack surface), you can produce hardened, sub-25MB production containers:

```dockerfile
# ─── Stage 1: Build & Compile Native Binary ───
FROM dart:stable AS builder
WORKDIR /app

# Cache package dependencies
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --no-precompile

# Copy application source
COPY . .

# Ensure all dependencies are resolved
RUN dart pub get --offline

# Compile to standalone native executable binary:
RUN dart compile exe bin/server.dart -o /app/bin/server

# ─── Stage 2: Distroless Production Runner ───
FROM gcr.io/distroless/cc-debian12:nonroot
WORKDIR /app

# Copy compiled native binary from builder
COPY --from=builder /app/bin/server /app/bin/server

# Expose microservice HTTP port
EXPOSE 8080

# Run as unprivileged non-root user
USER nonroot:nonroot

# Start native binary directly
ENTRYPOINT ["/app/bin/server"]
```

```bash
# Build and inspect container image size:
docker build -t enterprise-dart-microservice:latest .
docker images enterprise-dart-microservice:latest
# SIZE: ~24.8 MB (Ultra-compact, instant boot!)
```

---

## 3. Publishing Packages to `pub.dev` & Enterprise Registries

### 1. Preparing for `pub.dev` Publishing

Before publishing an open-source library to Google's official `pub.dev` registry:

1. **Verify Package Health (`pana`)**:
   ```bash
   dart pub global activate pana
   pana .
   # Inspect Pana Score (Aim for 140/140 points for maximum visibility)
   ```

2. **Verify License & README**:
   Ensure `LICENSE` (e.g. MIT/Apache-2.0), `README.md`, and `CHANGELOG.md` are present at the root.

3. **Dry-Run Validation**:
   ```bash
   dart pub publish --dry-run
   ```

4. **Publish**:
   ```bash
   dart pub publish
   ```

---

## 4. Hosting Private Enterprise Package Registries

For proprietary corporate code, avoid publishing to public `pub.dev`. Use a private registry (such as **Unpub**, **JFrog Artifactory**, or **AWS CodeArtifact**):

```yaml
# pubspec.yaml in enterprise consumer project:
dependencies:
  acme_core_auth:
    hosted:
      url: https://dart-packages.corp.acme.com
      name: acme_core_auth
    version: ^2.1.0
```

---

## 5. Enterprise GitHub Actions CI/CD Pipeline (`.github/workflows/deploy.yml`)

```yaml
name: Compile Native Dart Binary & Deploy Container

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  test-and-build-native:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v4

      - name: Setup Dart SDK
        uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install Dependencies
        run: dart pub get

      - name: Analyze & Lint Code
        run: dart analyze --fatal-infos

      - name: Run Automated Test Suite
        run: dart test

      - name: Compile Native Linux AOT Executable
        run: dart compile exe bin/server.dart -o build/server_linux

      - name: Upload Binary Artifact
        uses: actions/upload-artifact@v4
        with:
          name: native-binary
          path: build/server_linux

  docker-publish:
    needs: test-and-build-native
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build & Push Distroless Container
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/dart-service:latest
            ghcr.io/${{ github.repository }}/dart-service:${{ github.ref_name }}
```

---

## Enterprise Production Deployment Checklist

- [ ] **AOT Binary Compilation**: Always compile production servers using `dart compile exe` rather than running `dart run` in production.
- [ ] **Distroless Containerization**: Deploy native executables inside `gcr.io/distroless/cc-debian12:nonroot` to guarantee zero unpatched OS vulnerabilities.
- [ ] **Sound Null Safety Verification**: Ensure `analysis_options.yaml` enables `strict-casts`, `strict-inference`, and `strict-raw-types`.
- [ ] **Pana Score Audit**: For published packages, verify 140/140 Pana score for documentation, formatting, and dependency constraints.
- [ ] **Graceful Process Signals**: Intercept `ProcessSignal.sigterm` in your `main()` server to close socket pools and complete in-flight transactions before container termination.
