# Module 08: Generics, Type Bounds & Reified Type System

**Track:** Dart — Language & VM Architecture  
**Category:** Type Architecture, Generic Constraints & Reification

---

## 1. What Are Reified Generics?

In languages like Java, TypeScript, and C#, generics suffer from **Type Erasure**: generic type parameters exist only during compile-time checking and are completely erased into raw `Object` or `any` at runtime. In TypeScript, `(list as any) is Array<string>` cannot be checked at runtime.

In **Dart**, generics are **100% Reified**:
- Generic type arguments are **preserved in memory at runtime**.
- Type tests (`is List<String>`) execute with complete fidelity at runtime.
- You can inspect generic types, print `T.toString()`, and instantiate generic type containers safely.

```dart
void main() {
  final stringList = <String>['apple', 'banana'];
  final intList = <int>[1, 2, 3];

  // Reified Type Tests execute accurately at runtime:
  print(stringList is List<String>); // Prints: true
  print(stringList is List<int>);    // Prints: false

  print(stringList.runtimeType);     // Prints: List<String>
}
```

---

## 2. Generic Classes & Data Structures

```dart
class PriorityQueue<T extends Comparable<T>> {
  final List<T> _elements = [];

  void push(T element) {
    _elements.add(element);
    // Sort elements using the Comparable constraint:
    _elements.sort((a, b) => b.compareTo(a));
  }

  T? pop() {
    if (_elements.isEmpty) return null;
    return _elements.removeAt(0);
  }

  int get length => _elements.length;
  bool get isEmpty => _elements.isEmpty;

  @override
  String toString() => 'PriorityQueue<$T>($_elements)';
}
```

---

## 3. Generic Functions & Type Bounds

You can place bounds on generic functions using the **`extends`** keyword:

```dart
// 1. Generic Function with Number Bound:
T calculateSum<T extends num>(T a, T b) {
  return (a + b) as T;
}

// 2. Generic Cache Repository with Serializable Bound:
abstract class Serializable {
  Map<String, dynamic> toJson();
}

class CacheRepository<T extends Serializable> {
  final Map<String, Map<String, dynamic>> _storage = {};

  void save(String key, T entity) {
    _storage[key] = entity.toJson();
    print('Saved entity of type $T under key: $key');
  }
}
```

---

## 4. Generic Type Aliases (`typedef`)

```dart
// Generic Predicate Function:
typedef Predicate<T> = bool Function(T item);

// Generic Transformer:
typedef Transformer<TInput, TOutput> = TOutput Function(TInput input);

// Generic API Result Map:
typedef ApiResponse<T> = Map<String, Result<T>>;

void main() {
  final Predicate<int> isEven = (n) => n % 2 == 0;
  final Transformer<String, int> parser = (s) => int.parse(s);

  print(isEven(42));       // true
  print(parser('100') * 2); // 200
}
```

---

## 5. Covariance & The `covariant` Keyword

In Dart, generic collection types are **covariant**:
- If `Dog extends Animal`, then `List<Dog>` is considered a subtype of `List<Animal>`.

While covariant collections make UI programming (e.g. widget trees) intuitive, they can lead to runtime heap type errors if you insert an incompatible subtype into a widened list:

```dart
class Animal {}
class Dog extends Animal {}
class Cat extends Animal {}

void main() {
  List<Dog> dogs = [Dog()];
  List<Animal> animals = dogs; // Valid at compile time due to covariance!

  // ❌ Throws TypeError at runtime!
  // animals.add(Cat()); // 'Cat' is not a subtype of 'Dog' in List<Dog>!
}
```

### The `covariant` Keyword on Method Parameters:

Use `covariant` when a subclass legitimately needs to tighten the parameter type of an inherited method:

```dart
abstract class AnimalFeed {
  void eat(Animal animal);
}

class BoneFeed extends AnimalFeed {
  // 'covariant' tells the compiler it is intentional to restrict parameter to Dog:
  @override
  void eat(covariant Dog dog) {
    print('Dog is chewing bone.');
  }
}
```

---

## 6. Accessing Generic Type Names at Runtime

Because generics are reified, you can extract and inspect type parameters:

```dart
class ServiceLocator {
  final Map<Type, dynamic> _registry = {};

  void register<T>(T instance) {
    _registry[T] = instance;
    print('Registered service: $T');
  }

  T get<T>() {
    final instance = _registry[T];
    if (instance == null) {
      throw StateError('No service registered for type $T');
    }
    return instance as T;
  }
}
```

---

## Troubleshooting & Best Practices

1. **Avoid Unbounded Generic Downcasts**
   Never cast `(raw as T)` without first checking `if (raw is T)`. While the compiler might allow the cast, an invalid type will throw a `TypeError` at runtime.

2. **Prefer Explicit Generic Type Arguments**
   Write `final users = <User>[]` rather than `final users = []`. Explicit type annotations prevent Dart from defaulting to `List<dynamic>`.
