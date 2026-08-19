# Module 05: Mixins, Extension Methods & Operator Overloading

**Track:** Dart — Language & VM Architecture
**Category:** Metaprogramming, Linearization & Zero-Cost Abstractions

---

## 1. What Are Mixins?

A **Mixin** is a way of reusing a class's code in multiple class hierarchies without single-inheritance constraints.

Unlike standard inheritance (which creates a rigid vertical parent-child relationship), mixins allow horizontally composing behavioral capabilities (e.g. logging, serialization, validation) onto any class via the **`with`** keyword:

```dart
mixin Logger {
  void log(String message) {
    print('[${DateTime.now().toIso8601String()}] [${runtimeType.toString()}]: $message');
  }
}

mixin AuditTracker {
  int _mutationCount = 0;
  void recordMutation() => _mutationCount++;
  int get totalMutations => _mutationCount;
}

// Applying mixins via 'with':
class AccountService with Logger, AuditTracker {
  void transfer(double amount) {
    log('Transferring \$$amount');
    recordMutation();
  }
}
```

---

## 2. Restricting Mixins with the `on` Clause

Use the **`on`** clause to restrict a mixin so that it can **only be applied to classes that extend a specific superclass**:

```dart
abstract class UIComponent {
  void render();
}

// 'Draggable' can ONLY be mixed into classes that extend 'UIComponent'!
mixin Draggable on UIComponent {
  double x = 0;
  double y = 0;

  void moveTo(double newX, double newY) {
    x = newX;
    y = newY;
    // Can call methods from UIComponent safely:
    render();
  }
}

class ButtonComponent extends UIComponent with Draggable {
  @override
  void render() => print('Rendering button at ($x, $y)');
}
```

---

## 3. Extension Methods (Extending Existing APIs)

**Extension Methods** allow you to add new methods, getters, and operators to existing classes (including SDK types like `String`, `int`, `DateTime`, or third-party packages) without subclassing or modifying their source code:

```dart
// src/extensions/string_extensions.dart

extension StringFormatting on String {
  // 1. Extension Getter:
  bool get isValidEmail {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(this);
  }

  // 2. Extension Method:
  String truncate(int maxLength, {String ellipsis = '...'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}$ellipsis';
  }

  // 3. Extension Operator Overload:
  String operator *(int times) {
    return List.filled(times, this).join();
  }
}

extension IntTimeUnits on int {
  Duration get seconds => Duration(seconds: this);
  Duration get minutes => Duration(minutes: this);
  Duration get days => Duration(days: this);
}
```

### Consuming Extension Methods

```dart
void main() {
  final email = 'alice@example.com';
  print(email.isValidEmail); // Prints: true

  final longText = 'This is an enterprise Dart 3 language architectural manual.';
  print(longText.truncate(20)); // Prints: This is an enterpris...

  print('Dart! ' * 3); // Prints: Dart! Dart! Dart!

  final timeout = 30.seconds; // Duration(seconds: 30)
  print('Timeout: ${timeout.inSeconds}s');
}
```

---

## 4. Extension Types (Dart 3.3+ Zero-Cost Abstractions)

**Extension Types** provide compile-time type safety with **zero runtime memory allocation or wrapper object overhead**. The Dart compiler erases the extension type into the underlying primitive type in compiled machine code:

```dart
// Zero-cost type-safe wrapper around an integer representing an ID:
extension type const UserId(int rawId) {
  bool get isSystemAdmin => rawId == 0;
  void printId() => print('User #$rawId');
}

// Zero-cost type-safe wrapper around a double representing Currency:
extension type const Dollars(double amount) {
  int get inCents => (amount * 100).round();
  Dollars operator +(Dollars other) => Dollars(amount + other.amount);
}

void main() {
  final user = UserId(1042);
  final cost = Dollars(49.99);

  user.printId(); // User #1042
  print('Cents: ${cost.inCents}'); // Cents: 4999
}
```

---

## 5. Operator Overloading (`==`, `+`, `[]`, `hashCode`)

In Dart, mathematical, comparison, and indexing operators can be overloaded by defining custom operator methods:

```dart
class Vector2D {
  final double x;
  final double y;

  const Vector2D(this.x, this.y);

  // 1. Overloading the Addition Operator (+)
  Vector2D operator +(Vector2D other) {
    return Vector2D(this.x + other.x, this.y + other.y);
  }

  // 2. Overloading the Subtraction Operator (-)
  Vector2D operator -(Vector2D other) {
    return Vector2D(this.x - other.x, this.y - other.y);
  }

  // 3. Overloading the Index Operator ([])
  double operator [](int index) {
    if (index == 0) return x;
    if (index == 1) return y;
    throw RangeError.index(index, this, 'Index must be 0 (x) or 1 (y)');
  }

  // 4. Overloading Value Equality (==) and hashCode:
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vector2D &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vector2D($x, $y)';
}

void main() {
  final v1 = Vector2D(10, 20);
  final v2 = Vector2D(5, 5);

  final v3 = v1 + v2;
  print(v3); // Vector2D(15.0, 25.0)

  print(v3[0]); // 15.0 (x)
  print(v3[1]); // 25.0 (y)

  print(Vector2D(1, 2) == Vector2D(1, 2)); // true!
}
```

---

## Troubleshooting & Best Practices

1. **Always Override `hashCode` When Overriding `operator ==`**
   If two objects are considered equal (`a == b`), they **must** return the exact same `hashCode`. Failing to override `hashCode` causes objects to be lost inside `Set` and `Map` collections! Use `Object.hash(field1, field2)`.

2. **Use Extension Types for Unchecked JSON Boundaries**
   Use Dart 3.3+ `extension type` to wrap untyped JSON maps (`extension type JsonUser(Map<String, dynamic> raw)`) without allocating extra heap objects.
