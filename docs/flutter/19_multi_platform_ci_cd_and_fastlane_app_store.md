# Module 19: Multi-Platform CI/CD, Fastlane & App Store Deployment

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine  
**Category:** DevOps, Build Pipelines & App Store Publishing Automation

---

## 1. Multi-Platform Production Build Targets

Flutter can build optimized production distribution artifacts for all major operating systems from a single repository:

```bash
# 1. Android: Google Play Android App Bundle (AAB with split ABI architectures)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android

# 2. iOS: Signed IPA Archive for Apple TestFlight / App Store Connect
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios

# 3. Web: Modern WebAssembly (Wasm) + CanvasKit Build
flutter build web --release --wasm

# 4. Desktop Binaries:
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

---

## 2. Code Obfuscation & Symbol Stripping

For security-sensitive commercial apps, obfuscate Dart identifiers to protect intellectual property against reverse-engineering tools:

```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols
```
This strips human-readable function/class names and outputs a symbol map file for de-obfuscating crash stack traces in Crashlytics or Sentry.

---

## 3. Automated Code Signing & Deployment with Fastlane

**Fastlane** is the industry standard for automating iOS certificates, provisioning profiles, and automated store submissions:

```ruby
# android/fastlane/Fastfile
default_platform(:android)

platform :android do
  desc "Build and deploy release AAB to Google Play Internal Track"
  lane :deploy_internal do
    sh("flutter build appbundle --release")
    upload_to_play_store(
      track: 'internal',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )
  end
end
```

```ruby
# ios/fastlane/Fastfile
default_platform(:ios)

platform :ios do
  desc "Sync certificates, build signed IPA, and upload to TestFlight"
  lane :beta do
    # 1. Sync certificates securely via Git with Fastlane Match:
    match(type: "appstore", readonly: true)

    # 2. Build signed iOS IPA:
    sh("flutter build ipa --release --export-options-plist=ios/ExportOptions.plist")

    # 3. Upload to Apple TestFlight:
    upload_to_testflight(
      ipa: "../build/ios/ipa/my_app.ipa",
      skip_waiting_for_build_processing: true
    )
  end
end
```

---

## 4. Multi-Platform GitHub Actions CI/CD Pipeline (`.github/workflows/deploy.yml`)

This multi-platform GitHub Actions workflow runs automated validation, builds Android, iOS, and Web artifacts in parallel matrix jobs, and publishes them:

```yaml
name: Flutter Multi-Platform CI/CD Pipeline

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  # ─── Job 1: Lint, Analyze & Test ───
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter SDK
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Install Dependencies
        run: flutter pub get

      - name: Analyze & Lint Code
        run: flutter analyze --fatal-infos

      - name: Run Widget & Unit Tests
        run: flutter test --coverage

  # ─── Job 2: Build Android Release ───
  build-android:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Decode Keystore
        run: |
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > android/app/upload-keystore.jks

      - name: Build Android AppBundle
        env:
          KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
        run: flutter build appbundle --release

      - name: Upload Android Artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-release.aab
          path: build/app/outputs/bundle/release/app-release.aab

  # ─── Job 3: Build Web Wasm Release ───
  build-web:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Build Web Wasm
        run: flutter build web --release --wasm

      - name: Deploy Web to Cloudflare Pages
        uses: cloudflare/pages-action@v1
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          projectName: my-flutter-web-app
          directory: build/web
```

---

## Production Deployment Checklist

- [ ] **Semantic Versioning**: Update `version: 1.2.0+42` in `pubspec.yaml` (Name: `1.2.0`, Build Number: `42`).
- [ ] **Code Obfuscation**: Enable `--obfuscate --split-debug-info` on all mobile production builds.
- [ ] **App Store Privacy Manifests**: Ensure iOS `PrivacyInfo.xcprivacy` and Android privacy policies are packaged.
- [ ] **ProGuard & R8 Rules**: Verify that native Android dependencies have their keep rules configured in `proguard-rules.pro`.
- [ ] **WebAssembly Support**: Ensure web hosting servers serve `.wasm` files with `Content-Type: application/wasm` and COOP/COEP cross-origin isolation headers.
