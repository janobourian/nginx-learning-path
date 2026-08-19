# Module 04: Inheritance, Abstract Classes & Dart 3 Class Modifiers

**Track:** Dart — Language & VM Architecture
**Category:** OOP Architecture, Implicit Interfaces & Class Modifiers

---

## 1. Inheritance & Method Overriding

In Dart, a class can extend a single superclass via `extends`:

```dart
abstract class StorageEngine {
  final String clusterName;

  StorageEngine(this.clusterName);

  // Abstract method:
  Future<void> write(String key, List<int> bytes);
  Future<List<int>?> read(String key);

  // Concrete method:
  void logDiagnostics() {
    print('[StorageEngine: $clusterName] Telemetry active.');
  }
}

class S3StorageEngine extends StorageEngine {
  final String bucket;

  S3StorageEngine({
    required String clusterName,
    required this.bucket,
  }) : super(clusterName);

  @override
  Future<void> write(String key, List<int> bytes) async {
    print('Writing ${bytes.length} bytes to S3 bucket $bucket at key: $key');
  }

  @override
  Future<List<int>?> read(String key) async {
    print('Reading key $key from S3 bucket $bucket');
    return [0x01, 0x02];
  }
}
```

---

## 2. Implicit Interfaces (`implements`)

In Dart, **every class implicitly defines an interface** containing all of its public instance methods and fields. You do not need a separate `interface` keyword to implement a class interface:

```dart
class UserRepository {
  Future<Map<String, dynamic>> findUser(String id) async => {};
  Future<void> saveUser(String id, Map<String, dynamic> data) async {}
}

// Mock implementation implementing the implicit interface of UserRepository:
class MockUserRepository implements UserRepository {
  final Map<String, Map<String, dynamic>> _storage = {};

  @override
  Future<Map<String, dynamic>> findUser(String id) async {
    return _storage[id] ?? {};
  }

  @override
  Future<void> saveUser(String id, Map<String, dynamic> data) async {
    _storage[id] = data;
  }
}
```

---

## 3. The Dart 3 Class Modifier System

Dart 3 introduced a comprehensive set of **Class Modifiers** that allow library authors to strictly control whether classes can be extended, implemented, constructed, or mixed in:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                       Dart 3 Class Modifiers                            │
├────────────────────┬──────────┬────────────┬─────────────┬──────────────┤
│ **Modifier**       │ Construct│ **Extend** │**Implement**│ **Mix In**   │
├────────────────────┼──────────┼────────────┼─────────────┼──────────────┤
│ **`class`**        │ Yes      │ Yes        │ Yes         │ No           │
├────────────────────┼──────────┼────────────┼─────────────┼──────────────┤
│ **`base class`**   │ Yes      │ **Yes**    │ **No**      │ No           │
├────────────────────┼──────────┼────────────┼─────────────┼──────────────┤
│ **`interface class`**│ Yes    │ **No**     │ **Yes**     │ No           │
├────────────────────┼──────────┼────────────┼─────────────┼──────────────┤
│ **`final class`**  │ Yes      │ **No**     │ **No**      │ No           │
├────────────────────┼──────────┼────────────┼─────────────┼──────────────┤
│ **`sealed class`** │ **No**   │ Inside lib │ Inside lib  │ No           │
└────────────────────┴──────────┴────────────┴─────────────┴──────────────┘
*(Note: Restrictions apply to code outside the library where the class is declared.)*
```

---

## 4. Deep Dive: Class Modifiers in Action

### 1. `interface class` (Enforce Pure Interface Implementation)

Use `interface class` when you want third-party packages to **implement** your API contract, but forbid them from inheriting internal implementation code via `extends`:

```dart
// lib/payment_gateway.dart
interface class PaymentGateway {
  Future<bool> processPayment(double amount) async => false;
}

// In external package:
// class StripeGateway extends PaymentGateway {} // ❌ Compile Error: Cannot extend interface class!
class StripeGateway implements PaymentGateway { // ✅ Valid!
  @override
  Future<bool> processPayment(double amount) async => true;
}
```

### 2. `base class` (Enforce Subclass Inheritance)

Use `base class` when your class relies on private internal state and lifecycle hooks, guaranteeing that consumers can only `extend` it and cannot break your contract via `implements`:

```dart
base class AudioPlugin {
  void init() {
    _nativeSetup();
  }

  void _nativeSetup() => print('Native audio bridge connected');
}
```

### 3. `final class` (Close Class from Any Subclassing)

Use `final class` for security-sensitive or performance-critical classes (like cryptographic keys or mathematical vectors) to prevent tampering:

```dart
final class CryptoSecretKey {
  final List<int> rawBytes;
  const CryptoSecretKey(this.rawBytes);
}
// Cannot be extended OR implemented by any external file!
```

---

## 5. Composition vs Inheritance in Enterprise Dart

While inheritance is useful for core base frameworks, enterprise Dart code heavily favors **Composition**:

```dart
class OrderService {
  final StorageEngine _storage;
  final PaymentGateway _gateway;

  // Injected dependencies composed cleanly:
  OrderService({
    required StorageEngine storage,
    required PaymentGateway gateway,
  }) : _storage = storage,
       _gateway = gateway;

  Future<bool> checkout(String orderId, double amount) async {
    final success = await _gateway.processPayment(amount);
    if (success) {
      await _storage.write(orderId, [0x01]);
    }
    return success;
  }
}
```

---

## Troubleshooting & Best Practices

1. **`extends` vs `implements`**

   - Use **`extends`** when you want to reuse code, fields, and constructors from the superclass.
   - Use **`implements`** when you want to fulfill a type contract without inheriting any implementation code.

2. **Always Annotate with `@override`**
   Always use `@override` when overriding a method or getter. If the parent class method signature changes in a future SDK update, `@override` guarantees that the compiler catches the breaking change immediately.
