# Module 03: Classes, Constructors & Factory Design Patterns

**Track:** Dart — Language & VM Architecture
**Category:** Object-Oriented Design, Constructor Architectures & Memory Allocation

---

## 1. Class Structure & Initializer Lists

In Dart, all classes inherit from `Object`. Field initialization in Dart occurs in a strict order:

1. **Field Initializers** & Default Values
2. **Initializer List** (Executed *before* constructor body and *before* `super()`)
3. **Superclass Constructor**
4. **Constructor Body**

```dart
class DatabaseConfig {
  final String host;
  final int port;
  final String connectionUrl;

  // Constructor with Initializer List:
  DatabaseConfig({
    required this.host,
    this.port = 5432,
  }) : assert(port > 0 && port < 65536, 'Port must be between 1 and 65535'),
       connectionUrl = 'postgres://$host:$port/production' {
    // Constructor Body (Runs after all fields are initialized!)
    print('DatabaseConfig initialized: $connectionUrl');
  }
}
```

---

## 2. The Full Suite of Dart Constructors

Dart provides five distinct constructor types designed for different memory and instantiation patterns:

```text
┌─────────────────────────────────────────────────────────────┐
│                 Dart Constructor Architecture               │
├─────────────────────┬───────────────────────────────────────┤
│ **Generative**      │ Standard constructor creating a new   │
│                     │ instance (`User(this.name)`).         │
├─────────────────────┼───────────────────────────────────────┤
│ **Named**           │ Provides explicit intent              │
│                     │ (`User.fromJson(map)`, `User.guest()`)│
├─────────────────────┼───────────────────────────────────────┤
│ **`const`**         │ Canonicalized compile-time constant;  │
│                     │ zero runtime heap allocation!         │
├─────────────────────┼───────────────────────────────────────┤
│ **Redirecting**     │ Forwards arguments to another         │
│                     │ constructor (`this(...)`).            │
├─────────────────────┼───────────────────────────────────────┤
│ **Factory**         │ Does not always create a new instance;│
│                     │ returns cached instances or subtypes. │
└─────────────────────┴───────────────────────────────────────┘
```

---

## 3. Deep Dive: Named & Redirecting Constructors

```dart
class UserAccount {
  final String id;
  final String username;
  final String role;
  final DateTime createdAt;

  // 1. Primary Generative Constructor:
  const UserAccount({
    required this.id,
    required this.username,
    this.role = 'member',
    required this.createdAt,
  });

  // 2. Named Constructor (JSON Deserialization):
  UserAccount.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        username = json['username'] as String,
        role = (json['role'] as String?) ?? 'member',
        createdAt = DateTime.parse(json['created_at'] as String);

  // 3. Redirecting Constructor:
  UserAccount.anonymous()
      : this(
          id: 'anon_000',
          username: 'Guest_User',
          role: 'guest',
          createdAt: DateTime.now(),
        );

  // Immutable copyWith pattern:
  UserAccount copyWith({
    String? username,
    String? role,
  }) {
    return UserAccount(
      id: this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      createdAt: this.createdAt,
    );
  }
}
```

---

## 4. Factory Constructors & The Singleton Pattern

Unlike standard constructors (which *must* allocate and return a brand-new instance of the current class), a **`factory` constructor**:

- Can return an existing instance from an in-memory cache (Singleton Pattern).
- Can return an instance of a subclass.
- Can perform asynchronous or complex pre-processing logic before returning.

```dart
class CacheManager {
  final String namespace;
  final Map<String, dynamic> _memoryCache = {};

  // Static in-memory cache of singleton instances:
  static final Map<String, CacheManager> _instances = {};

  // Private Generative Constructor:
  CacheManager._internal(this.namespace);

  // Factory Constructor (Returns existing singleton if already instantiated!):
  factory CacheManager(String namespace) {
    return _instances.putIfAbsent(
      namespace,
      () => CacheManager._internal(namespace),
    );
  }

  void put(String key, dynamic value) => _memoryCache[key] = value;
  dynamic get(String key) => _memoryCache[key];
}

void main() {
  // Both point to the exact same instance in memory:
  final cache1 = CacheManager('auth');
  final cache2 = CacheManager('auth');

  print(identical(cache1, cache2)); // Prints: true!
}
```

---

## 5. Getters, Setters & Computed Properties

```dart
class FinancialTransaction {
  final double amountInDollars;
  final String currency;

  FinancialTransaction({
    required this.amountInDollars,
    this.currency = 'USD',
  });

  // Computed Getter:
  int get amountInCents => (amountInDollars * 100).round();

  // Custom Formatter Getter:
  String get formattedDisplay => '$currency ${amountInDollars.toStringAsFixed(2)}';
}
```

---

## Troubleshooting & Best Practices

1. **Prefer `const` Constructors for All Immutable Classes**
   If all fields of a class are `final`, add `const` to the constructor. This allows consumers to instantiate `const MyClass()` and save memory.

2. **Factory Constructors Cannot Access `this`**
   Factory constructors do not have an active instance binding when invoked, so accessing `this` inside a `factory` constructor body will throw a compiler error. Return an explicitly constructed instance instead.
