# Module 01: Language Syntax, Variables, Types & Operators

**Track:** Dart — Language & VM Architecture  
**Category:** Language Fundamentals, Type Hierarchy & Modern Dart 3 Syntax

---

## 1. Variable Declarations: `var`, `final`, `const` & `late`

Dart is a strongly, statically typed language with powerful local type inference.

```
┌─────────────────────────────────────────────────────────────┐
│                 Variable Declaration Matrix                 │
├──────────┬──────────────────────┬───────────────────────────┤
│ **`var`**  │ Inferred Type        │ Mutable (can be reassigned│
│          │                      │ to values of same type).  │
├──────────┼──────────────────────┼───────────────────────────┤
│ **`final`**│ Runtime Constant     │ Immutable (can be assigned│
│          │                      │ exactly once at runtime). │
├──────────┼──────────────────────┼───────────────────────────┤
│ **`const`**│ Compile-Time Const   │ Deeply immutable &        │
│          │                      │ canonicalized in memory!  │
├──────────┼──────────────────────┼───────────────────────────┤
│ **`late`** │ Deferred Init        │ Initialized lazily upon   │
│          │                      │ first access.             │
└──────────┴──────────────────────┴───────────────────────────┘
```

### `final` vs `const` Deep Dive:

```dart
void main() {
  // final: evaluated at RUNTIME (e.g. current system clock or HTTP response)
  final currentTime = DateTime.now(); // Valid!

  // const: must be known at COMPILE-TIME
  // const invalidTime = DateTime.now(); // ❌ Compile Error: DateTime.now() is not a const!
  const maxRetries = 3; // Valid!

  // const Canonicalization:
  // Both point to the EXACT same memory address in VM heap:
  const listA = [1, 2, 3];
  const listB = [1, 2, 3];
  print(identical(listA, listB)); // Prints: true!
}
```

### `late` Initialization & Lazy Evaluation:

```dart
class DatabaseService {
  // 'late' defers execution of _connectToCluster until config is first read:
  late final ConnectionPool pool = _connectToCluster();

  ConnectionPool _connectToCluster() {
    print('Connecting to PostgreSQL cluster...');
    return ConnectionPool();
  }
}
```

---

## 2. The Dart Type Hierarchy

In Dart, **everything is an object** (including numbers, booleans, and functions), inheriting from `Object?`.

```
                  [Object?]  ◄── Top Type (Can be null)
                     │
                  [Object]   ◄── Top Non-Nullable Type
            ┌────────┼────────┐
         [num]    [String]  [bool]
         /   \
      [int] [double]
         \   /
        [Never]              ◄── Bottom Type (Function that throws / terminates)
```

### Core Data Types:

| Type | Size / Representation | Example |
| :--- | :--- | :--- |
| **`int`** | 64-bit signed integer | `int count = 42;` |
| **`double`** | 64-bit IEEE 754 float | `double price = 19.99;` |
| **`num`** | Parent of `int` and `double` | `num val = 10; val = 12.5;` |
| **`String`** | UTF-16 code units | `String name = "Dart 3";` |
| **`bool`** | `true` or `false` | `bool isActive = true;` |
| **`Never`** | Represents unreachable code / fatal errors | `Never fail() => throw Exception();` |

---

## 3. String Manipulation & String Interpolation

```dart
void main() {
  final user = 'Alice';
  final points = 250;

  // 1. Basic & Expression Interpolation:
  final greeting = 'Hello, $user! Score: ${points * 2}';

  // 2. Multi-line Strings:
  final sqlQuery = '''
    SELECT id, email, created_at
    FROM users
    WHERE active = true
    ORDER BY created_at DESC;
  ''';

  // 3. Raw Strings (Ignores escape sequences like \n or \t):
  final regexPattern = r'^\w+@[a-zA-Z_]+?\.[a-zA-Z]{2,3}$';

  print(greeting);
  print(sqlQuery);
  print(regexPattern);
}
```

---

## 4. Special Operators: Cascade, Null-Aware & Spread

### 1. Cascade (`..`) & Null-Aware Cascade (`?..`)

The cascade operator (`..`) allows performing a sequence of operations on the same object without intermediate variables:

```dart
class StringBuilder {
  final List<String> _parts = [];
  void append(String s) => _parts.add(s);
  void clear() => _parts.clear();
  String build() => _parts.join('');
}

void main() {
  final builder = StringBuilder()
    ..append('Dart ')
    ..append('Cascade ')
    ..append('Engine');

  print(builder.build()); // Prints: Dart Cascade Engine
}
```

### 2. Spread (`...`) and Null-Aware Spread (`...?`)

```dart
final baseRoles = ['viewer', 'editor'];
List<String>? extraRoles;

final allRoles = [
  'admin',
  ...baseRoles,
  ...?extraRoles, // Safely skipped if extraRoles is null!
];
```

---

## 5. Functions & Parameter Architectures

Dart functions support **Named Parameters**, **Default Values**, and **Positional Parameters**:

```dart
// 1. Named Parameters with 'required' and defaults:
void configureServer({
  required String host,
  int port = 8080,
  bool enableSsl = true,
  Duration? timeout,
}) {
  print('Server starting at $host:$port (SSL: $enableSsl)');
}

// 2. Positional Optional Parameters (enclosed in []):
String formatLog(String message, [String level = 'INFO', DateTime? timestamp]) {
  final time = timestamp ?? DateTime.now();
  return '[$level] [$time] $message';
}

// 3. First-Class Functions & Arrow Syntax:
int Function(int) createMultiplier(int factor) {
  return (int value) => value * factor;
}

void main() {
  configureServer(host: '0.0.0.0', port: 9000);

  final doubler = createMultiplier(2);
  print(doubler(21)); // 42
}
```

---

## Troubleshooting & Best Practices

1. **Avoid `dynamic` — Prefer `Object?`**
   - `dynamic`: Completely turns off static type checking. Errors will crash at runtime.
   - `Object?`: Tells the compiler "this can be any value, but you must narrow or cast it safely before calling methods on it".

2. **Use `const` Constructors Everywhere Possible**
   Using `const` allows the Dart VM to allocate objects once at compile time and share the exact same instance in memory across the entire application runtime.
