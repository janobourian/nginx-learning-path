# Module 02: Sound Null Safety & Control Flow Analysis

**Track:** Dart — Language & VM Architecture
**Category:** Type System, Sound Null Safety & Flow Analysis

---

## 1. What Is Sound Null Safety?

Before Dart 2.12, like Java and TypeScript, `null` was a valid value for any reference type. A variable typed as `String` could secretly hold `null`, causing catastrophic `NullPointerExceptions` at runtime.

In modern **Dart 3**, **Sound Null Safety is 100% mandatory**:

1. **Non-Nullable by Default**: `String name = "Alice";` can **never** hold `null`. Attempting to assign `null` will fail at compile time.
2. **Explicit Nullability**: To allow `null`, you must explicitly suffix the type with `?` (`String? nullableName = null;`).
3. **100% Soundness**: The compiler guarantees that a non-nullable variable can *never* be `null` at runtime. In AOT compiled machine code, the Dart VM **completely eliminates redundant null checks**, resulting in smaller binaries and up to 20% faster CPU execution!

```text
Dart Type System:
Non-Nullable: [int]    [String]    [User]    [List<int>]  ◄── Can NEVER be null!
Nullable:     [int?]   [String?]   [User?]   [List<int>?] ◄── Must be checked before access!
```

---

## 2. The Null-Aware Operator Suite

| Operator | Name | Purpose | Example |
| :--- | :--- | :--- | :--- |
| **`?.`** | **Null-Aware Access** | Invokes method/getter only if target is not null | `user?.profile?.avatarUrl` |
| **`??`** | **Null-Coalescing** | Returns fallback value if expression is null | `final name = input ?? "Guest";` |
| **`??=`** | **Null-Coalescing Assign** | Assigns value only if variable is currently null | `cachedData ??= fetchFromApi();` |
| **`?[]`** | **Null-Aware Index** | Safely indexes into a nullable list/map | `items?[0]` |
| **`!`** | **Null Assertion (Bang)** | Forces non-null cast; **throws runtime error if null!** | `user!.save()` |

### Code Examples

```dart
void main() {
  String? nullableCity;

  // 1. Null-coalescing fallback:
  final currentCity = nullableCity ?? 'San Francisco';
  print(currentCity); // San Francisco

  // 2. Null-coalescing assignment:
  nullableCity ??= 'Austin';
  print(nullableCity); // Austin

  // 3. Null-aware method calling:
  final length = nullableCity?.toUpperCase().length;
  print('Length: $length'); // Length: 6
}
```

---

## 3. Control Flow Analysis & Type Promotion

The Dart compiler features sophisticated **Type Flow Analysis**. When you check whether a nullable variable is null, the compiler automatically **promotes** the variable from `Type?` to `Type` for the remainder of that control flow scope:

```dart
void processUserProfile(String? rawInput) {
  // rawInput is String? here:
  // print(rawInput.length); // ❌ Compile Error!

  if (rawInput == null) {
    print('No profile input provided.');
    return;
  }

  // ◄── Automatic Type Promotion!
  // The compiler knows rawInput cannot be null after the return statement:
  print('Input Length: ${rawInput.length}'); // ✅ Valid! Promoted to String!
  print('Uppercase: ${rawInput.toUpperCase()}');
}
```

### Type Promotion with `is` Type Tests

```dart
void handlePayload(Object data) {
  if (data is String) {
    // data is automatically promoted to String:
    print('String length: ${data.length}');
  } else if (data is List<int>) {
    // data is automatically promoted to List<int>:
    print('Integer sum: ${data.fold(0, (a, b) => a + b)}');
  }
}
```

---

## 4. Why Public Class Fields Cannot Be Promoted (And How to Fix It)

A common point of confusion in Dart is why class fields cannot be automatically promoted:

```dart
class AccountManager {
  String? authToken;

  void executeTransfer() {
    if (authToken != null) {
      // ❌ Compile Error in older Dart: The property 'authToken' cannot be promoted!
      // print(authToken.length);
    }
  }
}
```

### Why does this happen?

Because another method, subclass override, or concurrent isolate could theoretically modify the field between the `if` check and the method call.

### The Solution: Shadow with a Local Variable (or Private Fields in Dart 3.2+)

```dart
class AccountManager {
  String? authToken;

  void executeTransfer() {
    // Shadow field into a local final variable:
    final token = authToken;

    if (token != null) {
      // Local variables are 100% guaranteed immutable and promote cleanly!
      print('Executing transfer with token length: ${token.length}');
    }
  }
}
```

*(Note: In Dart 3.2+, private final class fields `_authToken` promote automatically if they have no custom getter overrides!)*

---

## 5. Working with Nullable Collections

Be careful where the `?` is placed in generic collection types:

```dart
// 1. List is NOT null, but can contain null elements:
List<String?> namesWithNulls = ['Alice', null, 'Charlie'];

// 2. List CAN be null, but its elements cannot be null:
List<String>? nullableList = null;

// 3. Both the List AND its elements can be null:
List<String?>? completelyNullableList = [null, 'Bob'];
```

---

## Troubleshooting & Best Practices

1. **Avoid the Bang Operator (`!`)**
   Overusing `!` (e.g. `user!.profile!.email!`) defeats the purpose of sound null safety. If an unexpected `null` arrives, it will crash your application at runtime. Use `if` checks, `??` defaults, or pattern matching instead.

2. **Prefer Non-Nullable by Default**
   Design your data classes so that all fields are non-nullable by default, using `required` constructor parameters unless a value genuinely represents absence.
