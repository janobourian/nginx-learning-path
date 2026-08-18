# Module 06: Dart 3 Modern Primitives — Sealed Classes, Records & Pattern Matching

**Track:** Dart — Language & VM Architecture  
**Category:** Modern Type Primitives, Algebraic Data Types & Pattern Matching

---

## 1. The Dart 3 Language Revolution

Dart 3 represents the largest evolution of the Dart language since Sound Null Safety, introducing:
1. **Records**: Anonymous, aggregate, immutable tuple types with built-in value equality.
2. **Sealed Classes**: Closed class hierarchies enabling Algebraic Data Types (ADTs).
3. **Pattern Matching & Destructuring**: Ergonomic extraction and inspection of complex data structures.
4. **Switch Expressions**: Declarative, expression-based pattern matching with **compiler-enforced exhaustiveness**.

---

## 2. Records (Immutable Aggregate Types)

Before Dart 3, returning multiple values from a function required either creating a dedicated class (`Pair`, `Tuple`, `Coordinates`) or returning an untyped `List<dynamic>`.

**Records** are lightweight, anonymous, immutable compound types:

```dart
// 1. Positional Records:
(String, int) getUserInfo() {
  return ('Alice', 28);
}

// 2. Named Records:
({String host, int port, bool isSecure}) getDatabaseConfig() {
  return (host: 'db.example.com', port: 5432, isSecure: true);
}

// 3. Mixed Positional & Named Records:
(String name, {int age, String role}) getAdminProfile() {
  return ('Bob', age: 34, role: 'admin');
}
```

### Accessing Record Fields & Destructuring:

```dart
void main() {
  // Accessing positional fields ($1, $2):
  final user = getUserInfo();
  print('${user.$1} is ${user.$2} years old.'); // Alice is 28 years old.

  // Accessing named fields:
  final config = getDatabaseConfig();
  print('Connecting to ${config.host}:${config.port} (SSL: ${config.isSecure})');

  // Destructuring a Record directly:
  final (name, age) = getUserInfo();
  print('Destructured: $name, $age');

  // Value Equality (Built-in!):
  print(('A', 1) == ('A', 1)); // Prints: true!
}
```

---

## 3. Sealed Classes & Algebraic Data Types (ADTs)

A **`sealed class`** creates a closed subtype hierarchy. All subclasses **must be declared in the same library/file**.

Because the compiler knows every possible subclass, it enforces **exhaustive pattern matching**:

```dart
// Sealed Base Class (Cannot be instantiated directly):
sealed class NetworkResult<T> {}

class Success<T> extends NetworkResult<T> {
  final T data;
  final int statusCode;
  Success(this.data, {this.statusCode = 200});
}

class ClientError<T> extends NetworkResult<T> {
  final String message;
  final int code;
  ClientError(this.message, this.code);
}

class ServerError<T> extends NetworkResult<T> {
  final String stackTrace;
  ServerError(this.stackTrace);
}

class Loading<T> extends NetworkResult<T> {}
```

---

## 4. Switch Expressions & Compiler Exhaustiveness Checking

A **Switch Expression** evaluates patterns and returns a value. If you forget to handle even a single subclass of a `sealed class`, the Dart compiler **refuses to compile**:

```dart
String renderStatusMessage(NetworkResult<String> result) {
  // Switch Expression returning a String:
  return switch (result) {
    Success(:final data, :final statusCode) => 'Data fetched successfully ($statusCode): $data',
    ClientError(:final message, :final code) => 'Client Error [$code]: $message',
    ServerError(:final stackTrace) => 'Internal Server Error. Diagnostic trace: $stackTrace',
    Loading() => 'Fetching resource from edge...',
    // No 'default' needed! The compiler proves all branches are exhausted!
  };
}
```

---

## 5. Pattern Matching & `if-case` Destructuring

Pattern matching allows unpacking complex nested data (JSON, Maps, Lists, Objects) declaratively:

### 1. JSON Destructuring with `if-case`:

```dart
void processIncomingWebhook(Map<String, dynamic> json) {
  // Match exact map shape and extract fields into typed local variables:
  if (json case {
    'event': 'user_created',
    'payload': {'id': String userId, 'email': String email},
  }) {
    print('New user registered: $userId ($email)');
  } else if (json case {'event': 'payment_success', 'amount': num amount} when amount > 1000) {
    // Guard clause using 'when':
    print('High-value payment processed: \$$amount');
  } else {
    print('Unhandled webhook event.');
  }
}
```

### 2. List Pattern Matching with Rest Elements (`...`):

```dart
void analyzeLogSequence(List<String> logs) {
  switch (logs) {
    case ['START', ...final middle, 'FINISH']:
      print('Standard batch completed with ${middle.length} intermediate tasks.');
    case ['ERROR', ...final details]:
      print('Batch failed with error details: $details');
    case []:
      print('Empty log stream.');
    default:
      print('Unknown log sequence pattern.');
  }
}
```

### 3. Object Pattern Matching & Field Extractors:

```dart
class Point {
  final double x;
  final double y;
  const Point(this.x, this.y);
}

String describePoint(Point p) {
  return switch (p) {
    Point(x: 0, y: 0) => 'Origin',
    Point(x: 0, :final y) => 'On Y-axis at $y',
    Point(:final x, y: 0) => 'On X-axis at $x',
    Point(:final x, :final y) when x == y => 'On Diagonal at $x',
    Point(:final x, :final y) => 'Quadrant point at ($x, $y)',
  };
}
```

---

## Troubleshooting & Best Practices

1. **Do NOT add redundant `default:` branches to Sealed Class switches**
   Adding a `default` case to a sealed class switch turns off compile-time exhaustiveness checking. If you add a new subclass in the future, the compiler will silently fall back to `default` instead of warning you to handle the new case!

2. **Use Records for Multiple Function Return Values**
   Prefer `(bool success, String? error)` over custom 2-field data transfer classes.
