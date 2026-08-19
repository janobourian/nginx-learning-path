# Module 00: Dart SDK Installation, Toolchain & `pubspec.yaml` Mastery

**Track:** Dart — Language & VM Architecture
**Category:** Toolchain, Package Management & Development Environment

---

## 1. What Is Dart?

**Dart** is a client-optimized, object-oriented language developed by Google, designed for high-speed multi-platform development across web, server, desktop, and mobile (powers the Flutter UI framework).

### Key Architectural Pillars of Dart 3

1. **100% Sound Null Safety**: Types cannot contain `null` unless explicitly marked (e.g. `String?`), allowing the compiler to perform aggressive optimizations and eliminate `NullPointerExceptions` at runtime.
2. **Dual-Compilation Modes**:

   - **JIT (Just-In-Time Compilation)** with Kernel AST in development for instant **Stateful Hot Reload**.
   - **AOT (Ahead-Of-Time Compilation)** in production for native machine code binaries (ARM64 / x86_64) with zero VM warm-up latency.
3. **Modern Language Primitives (Dart 3)**: Sealed class hierarchies, Records, Pattern Matching, Destructuring, and Mixin class inheritance.
4. **Shared-Nothing Isolate Concurrency**: Multi-threaded execution without shared-memory locks or race conditions.

---

## 2. Installing the Dart SDK

```bash

# macOS (Homebrew)
brew tap dart-lang/dart
brew install dart

# Linux (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y apt-transport-https
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | sudo tee /etc/apt/sources.list.d/dart_stable.list
sudo apt-get update && sudo apt-get install -y dart

# Verify installation
dart --version
```

---

## 3. The Dart CLI Command Suite

```bash

# 1. Create a new Dart console project
dart create -t console-full my_dart_project
cd my_dart_project

# 2. Run application in development (JIT mode)
dart run bin/main.dart

# 3. Analyze code for lints and type errors
dart analyze

# 4. Format code according to official Dart style guide (80 char line width)
dart format .

# 5. Run automated test suite
dart test

# 6. Compile to self-contained native executable binary (AOT mode)
dart compile exe bin/main.dart -o build/my_app_binary

# 7. Package management
dart pub get      # Install dependencies
dart pub upgrade  # Upgrade packages
dart pub outdated # Check for dependency updates
```

---

## 4. `pubspec.yaml` Configuration Deep Dive

The `pubspec.yaml` file defines project metadata, dependencies, assets, and SDK constraints:

```yaml
name: enterprise_dart_server
description: High-performance microservice engine powered by Dart 3 and Isolates.
version: 1.0.0
homepage: https://github.com/acme/dart-server
publish_to: 'none' # Prevent accidental publishing to pub.dev

environment:
  sdk: '^3.4.0' # Enforces Dart 3.4+ sound null safety

dependencies:
  # High-performance async HTTP router
  shelf: ^1.4.1
  shelf_router: ^1.1.4

  # Cryptography and hashing
  crypto: ^3.0.3

  # JSON serialization & schema
  json_annotation: ^4.9.0

  # PostgreSQL database driver
  postgres: ^3.1.2

dev_dependencies:
  # Official Google linter rules
  lints: ^3.0.0

  # Code generation runner
  build_runner: ^2.4.9
  json_serializable: ^6.8.0

  # Unit testing & mock library
  test: ^1.25.2
  mockito: ^5.4.4
```

---

## 5. Enterprise Linter Rules (`analysis_options.yaml`)

Enforce strict type rules and style consistency:

```yaml

# analysis_options.yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    missing_required_param: error
    missing_return: error
    todo: ignore

linter:
  rules:

    - always_declare_return_types
    - avoid_empty_else
    - avoid_relative_lib_imports
    - avoid_shadowing_type_parameters
    - avoid_types_as_parameter_names
    - cancel_subscriptions
    - close_sinks
    - prefer_const_constructors
    - prefer_final_fields
    - prefer_final_locals
    - prefer_is_empty
    - prefer_is_not_empty
    - unawaited_futures
    - unnecessary_null_aware_assignments
    - unnecessary_nullable_for_final_variable_declarations
```

---

## 6. First Complete Dart Application (`bin/main.dart`)

```dart
// bin/main.dart
import 'dart:io';

void main(List<String> arguments) {
  final startTime = DateTime.now();

  stdout.writeln('========================================');
  stdout.writeln('🚀 Starting Enterprise Dart 3 Engine...');
  stdout.writeln('========================================');

  // Inspect environment:
  final os = Platform.operatingSystem;
  final cores = Platform.numberOfProcessors;
  final dartVersion = Platform.version.split(' ').first;

  stdout.writeln('Host OS:          $os');
  stdout.writeln('CPU Cores:        $cores');
  stdout.writeln('Dart SDK Version: $dartVersion');

  final elapsed = DateTime.now().difference(startTime).inMilliseconds;
  stdout.writeln('Bootstrap completed in ${elapsed}ms.');
}
```

---

## Troubleshooting & Best Practices

1. **`strict-casts: true` in `analysis_options.yaml`**
   Always enable `strict-casts`, `strict-inference`, and `strict-raw-types`. This prevents dynamic downcasting and guarantees that the compiler catches type mismatches at compile time rather than crashing at runtime.

2. **Always check `unawaited_futures`**
   In Dart, failing to `await` a `Future` or handle its error can cause silent failures. Enabling the `unawaited_futures` lint rule warns you whenever a `Future` is not explicitly awaited or passed to `unawaited()`.
