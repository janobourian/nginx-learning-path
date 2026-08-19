# Module 07: Collections Framework, Collection-If & Functional `Iterable`

**Track:** Dart — Language & VM Architecture
**Category:** Data Structures, Collection Operators & Lazy Iterables

---

## 1. The Core Collection Hierarchy

Dart provides three primary collection types, all inheriting from or providing `Iterable<E>`:

```json
                      [Iterable<E>] (Lazy Sequence)
                            │
               ┌────────────┴────────────┐
               ▼                         ▼
           [List<E>]                 [Set<E>]
      (Ordered Sequence)         (Unique Elements)

     - Growable List             - LinkedHashSet (Default)
     - Fixed-length List         - HashSet (Unordered fast hash)
     - Unmodifiable List         - SplayTreeSet (Sorted BST)

                      [Map<K, V>] (Key-Value Dictionary)

                     - LinkedHashMap (Default insertion-order)
                     - HashMap (Fast O(1) hash bucket)
                     - SplayTreeMap (Sorted by key comparator)
```

---

## 2. Lists, Sets & Maps Construction

### 1. `List<T>` (Ordered Indexed Arrays)

```dart
void main() {
  // 1. Growable List (Default):
  final items = <String>['apple', 'banana'];
  items.add('orange');

  // 2. Fixed-Length List:
  final fixedList = List<int>.filled(5, 0, growable: false);
  fixedList[0] = 42;
  // fixedList.add(10); // ❌ Throws UnsupportedError (Cannot add to fixed-length list)

  // 3. Generated List:
  final squares = List<int>.generate(10, (index) => index * index);
  print(squares); // [0, 1, 4, 9, 16, 25, 36, 49, 64, 81]

  // 4. Truly Unmodifiable List:
  final immutableList = List<String>.unmodifiable(['READ', 'WRITE']);
  // immutableList[0] = 'EXEC'; // ❌ Throws UnsupportedError!
}
```

### 2. `Set<T>` (Unique Elements & Math Set Operations)

```dart
void main() {
  final groupA = {'admin', 'editor', 'moderator'};
  final groupB = {'editor', 'author', 'subscriber'};

  // Set Operations:
  final intersection = groupA.intersection(groupB); // {'editor'}
  final union = groupA.union(groupB);               // {'admin', 'editor', 'moderator', 'author', 'subscriber'}
  final difference = groupA.difference(groupB);     // {'admin', 'moderator'}

  print('Shared roles: $intersection');
}
```

### 3. `Map<K, V>` (Key-Value Dictionaries)

```dart
void main() {
  final userAges = <String, int>{
    'Alice': 28,
    'Bob': 34,
  };

  // putIfAbsent: Inserts value only if key is not already present
  userAges.putIfAbsent('Charlie', () => 40);

  // Map.fromEntries:
  final entries = [MapEntry('USD', 1.0), MapEntry('EUR', 0.92)];
  final currencyMap = Map<String, double>.fromEntries(entries);
}
```

---

## 3. Advanced Collection Operators: `collection-if` & `collection-for`

Dart allows embedding `if`, `if-else`, `for`, and `spread (...)` expressions directly inside collection literals. This is heavily utilized in UI declarations (Flutter) and configuration pipelines:

```dart
List<String> buildNavigationMenu({
  required bool isAuthenticated,
  required bool isAdmin,
  required List<String> customPluginRoutes,
}) {
  return [
    'Home',
    'About',
    // 1. Collection-if:
    if (isAuthenticated) 'Dashboard',

    // 2. Collection-if-else:
    if (isAuthenticated) 'Profile' else 'Login',

    // 3. Collection-if with complex check:
    if (isAuthenticated && isAdmin) ...[
      'Admin Settings',
      'User Management',
      'Audit Logs',
    ],

    // 4. Collection-for with transformation:
    for (final route in customPluginRoutes) 'Plugin: ${route.toUpperCase()}',
  ];
}
```

---

## 4. Lazy `Iterable` Functional Pipelines

In Dart, operations on `Iterable` (`map`, `where`, `take`, `expand`) are **lazy**: they do not execute immediately until the collection is actively iterated over or converted to a list via `.toList()`.

```dart
class Transaction {
  final String id;
  final double amount;
  final String category;

  const Transaction(this.id, this.amount, this.category);
}

void main() {
  final transactions = [
    Transaction('tx_1', 120.50, 'Electronics'),
    Transaction('tx_2', 15.00, 'Groceries'),
    Transaction('tx_3', 350.00, 'Electronics'),
    Transaction('tx_4', 8.50, 'Coffee'),
  ];

  // Lazy processing pipeline:
  final highValueElectronics = transactions
      // Filter items (where):
      .where((t) => t.category == 'Electronics')
      // Map to amount:
      .map((t) => t.amount)
      // Filter amounts > 100:
      .where((amount) => amount > 100.0);

  // Execution occurs here when fold() pulls elements:
  final totalSpent = highValueElectronics.fold<double>(
    0.0,
    (previousSum, amount) => previousSum + amount,
  );

  print('Total spent on high-value electronics: \$$totalSpent'); // $470.5
}
```

---

## 5. Defensive Copying & `UnmodifiableListView`

To protect private internal collection state from being mutated by external callers:

```dart
import 'dart:collection';

class ShoppingCart {
  final List<String> _items = [];

  // Expose an UnmodifiableListView wrapping the private list:
  UnmodifiableListView<String> get items => UnmodifiableListView(_items);

  void addItem(String item) => _items.add(item);
}
```

---

## Troubleshooting & Best Practices

1. **Avoid `.toList()` in Intermediate Pipeline Steps**
   Calling `.map(...).toList().where(...).toList()` allocates unnecessary temporary arrays in heap memory. Chain lazy iterable operators and call `.toList()` once at the very end of the pipeline.

2. **Use `Map.putIfAbsent()` for Caching**
   Avoid `if (!map.containsKey(k)) { map[k] = val; }`. Use `map.putIfAbsent(k, () => val)` which performs a single hash lookup instead of two.
