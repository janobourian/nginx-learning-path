# Module 15: Dart FFI — Foreign Function Interface & C/Rust Native Interop

**Track:** Dart — Language & VM Architecture
**Category:** Native Interop, Foreign Function Interface (`dart:ffi`) & Systems Programming

---

## 1. What Is Dart FFI?

**Dart FFI (`dart:ffi`)** provides direct, high-speed interoperability with native libraries written in **C, C++, Rust, Zig, or Go**.

Unlike traditional inter-process communication (IPC) or socket bridges, Dart FFI:

- Executes native shared library functions **within the same process address space**.
- Has **zero serialization or copying overhead**: passes raw memory pointers directly between Dart and C/Rust.
- Executes native CPU functions with near-zero bridge call overhead (~2 nanoseconds).

```text
Dart FFI Execution Architecture:
[Dart VM Runtime Heap]
       │
       ▼ (Direct Pointer Dereference via dart:ffi)
[Native Shared Library (*.dylib / *.so / *.dll)] ◄── Compiled C / Rust / Zig Code
```

---

## 2. Setting Up Dart FFI & Native Type Mappings

```yaml

# pubspec.yaml
dependencies:
  ffi: ^2.1.2 # Official Google FFI memory utilities (calloc, malloc, Utf8)
```

### Type Mapping Table (C to Dart)

| C Native Type (`dart:ffi`) | Dart Representation | Description |
| :--- | :--- | :--- |
| **`Int32`** | `int` | 32-bit signed integer |
| **`Int64`** | `int` | 64-bit signed integer |
| **`Float`** | `double` | 32-bit IEEE float |
| **`Double`** | `double` | 64-bit IEEE float |
| **`Pointer<T>`** | `Pointer<T>` | Raw memory address |
| **`Utf8`** (`package:ffi`) | `String` | Null-terminated C string (`char*`) |
| **`Struct`** | Subclass of `Struct` | C struct in native memory |
| **`NativeFunction<F>`** | Function signature | Native C function pointer |

---

## 3. Interfacing with a C Shared Library

Let's write and compile a high-performance C library:

```c
// native/crypto_engine.c

#include <stdint.h>

#include <string.h>

#include <stdlib.h>

// 1. Fast native addition
int32_t add_numbers(int32_t a, int32_t b) {
    return a + b;
}

// 2. String transformation (reverses string in-place)
void reverse_string(char* str) {
    int len = strlen(str);
    for (int i = 0; i < len / 2; i++) {
        char temp = str[i];
        str[i] = str[len - i - 1];
        str[len - i - 1] = temp;
    }
}
```

```bash

# Compile to dynamic shared library

# macOS
clang -shared -fPIC native/crypto_engine.c -o libcrypto_engine.dylib

# Linux
gcc -shared -fPIC native/crypto_engine.c -o libcrypto_engine.so
```

---

## 4. Binding Native Functions in Dart (`dart:ffi`)

```dart
// src/native/crypto_bindings.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// 1. Native C Function Signatures:
typedef NativeAddFunc = Int32 Function(Int32 a, Int32 b);
typedef NativeReverseFunc = Void Function(Pointer<Utf8> str);

// 2. Dart Function Signatures:
typedef DartAddFunc = int Function(int a, int b);
typedef DartReverseFunc = void Function(Pointer<Utf8> str);

class NativeCryptoEngine {
  late final DynamicLibrary _dylib;
  late final DartAddFunc _addNumbers;
  late final DartReverseFunc _reverseString;

  NativeCryptoEngine() {
    // 1. Load Dynamic Shared Library:
    final libraryPath = Platform.isMacOS
        ? 'libcrypto_engine.dylib'
        : (Platform.isWindows ? 'crypto_engine.dll' : 'libcrypto_engine.so');

    _dylib = DynamicLibrary.open(libraryPath);

    // 2. Lookup and bind C functions:
    _addNumbers = _dylib
        .lookup<NativeFunction<NativeAddFunc>>('add_numbers')
        .asFunction<DartAddFunc>();

    _reverseString = _dylib
        .lookup<NativeFunction<NativeReverseFunc>>('reverse_string')
        .asFunction<DartReverseFunc>();
  }

  int add(int a, int b) => _addNumbers(a, b);

  String reverse(String input) {
    // 1. Allocate native C string pointer in manual memory:
    final Pointer<Utf8> cString = input.toNativeUtf8();

    try {
      // 2. Call C function modifying memory in-place:
      _reverseString(cString);

      // 3. Convert back to Dart String:
      return cString.toDartString();
    } finally {
      // 4. CRITICAL: Free native memory allocation!
      malloc.free(cString);
    }
  }
}

void main() {
  final engine = NativeCryptoEngine();

  print('Native addition: ${engine.add(40, 2)}'); // 42
  print('Native reverse: ${engine.reverse('Enterprise Dart 3')}'); // 3 traD esirpretEnE
}
```

---

## 5. Working with Native C Structs

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Mapping C Struct:
// struct GeoCoordinate { double lat; double lng; int32_t altitude; };
final class GeoCoordinate extends Struct {
  @Double()
  external double latitude;

  @Double()
  external double longitude;

  @Int32()
  external int altitude;
}

void main() {
  // Allocate struct in native memory:
  final Pointer<GeoCoordinate> coordPtr = calloc<GeoCoordinate>();

  coordPtr.ref.latitude = 37.7749;
  coordPtr.ref.longitude = -122.4194;
  coordPtr.ref.altitude = 15;

  print('Allocated Native Coordinate: (${coordPtr.ref.latitude}, ${coordPtr.ref.longitude})');

  // Free memory:
  calloc.free(coordPtr);
}
```

---

## 6. Automatic Memory Cleanup with `NativeFinalizer` (Dart 2.17+)

Instead of manually tracking `malloc.free()`, **`NativeFinalizer`** attaches a native cleanup C function that is automatically invoked by the Dart Garbage Collector when the Dart wrapper object is collected:

```dart
import 'dart:ffi';

// Attach native free function to GC finalizer:
final NativeFinalizer nativeResourceFinalizer = NativeFinalizer(
  DynamicLibrary.process().lookup('free'),
);

class ManagedNativeResource {
  final Pointer<Void> _nativeHandle;

  ManagedNativeResource(this._nativeHandle) {
    // Register pointer for automatic GC cleanup:
    nativeResourceFinalizer.attach(this, _nativeHandle.cast(), detach: this);
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Free Native Allocations in `finally` Blocks**
   Memory allocated via `malloc` or `calloc` lives **outside** the Dart VM heap and is completely invisible to the Dart Garbage Collector. Failing to call `malloc.free(ptr)` will cause a persistent OS memory leak.

2. **Use `@Native` External Functions (Dart 3.1+)**
   In Dart 3.1+, use `@Native<Int32 Function(Int32)>(symbol: 'my_c_func') external int myCFunc(int x);` for direct statically linked AOT interop with zero lookup boilerplate.
