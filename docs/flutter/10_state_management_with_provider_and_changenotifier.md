# Module 10: State Management with `Provider` & `ChangeNotifier`

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine  
**Category:** State Architecture, InheritedWidgets & Provider Patterns

---

## 1. The Foundation of State: `InheritedWidget`

To understand `Provider`, you must understand **`InheritedWidget`**.

In Flutter, passing state down 15 levels of nested widgets via constructor parameters (prop drilling) is unmaintainable.

An **`InheritedWidget`** is a specialized widget built into the Flutter framework that allows any descendant child widget in the element tree to look up and subscribe to data above it in **O(1) time** using `BuildContext.dependOnInheritedWidgetOfExactType<T>()`:

```
InheritedWidget Tree Lookup (O(1) Hash Map Traversal):
[Root: MultiProvider] (InheritedElement)
        │
        ├── [HeaderWidget]
        └── [BodyWidget]
                │
                └── [DeeplyNestedButton] ──► context.watch<CartModel>() (Instant O(1) Lookup!)
```

The **`provider`** package wraps low-level `InheritedWidget` boilerplate into a clean, developer-friendly reactive API.

---

## 2. Setting Up `Provider` & `ChangeNotifier`

```yaml
# pubspec.yaml
dependencies:
  provider: ^6.1.2
```

### 1. Creating the Domain State (`ChangeNotifier`)

A **`ChangeNotifier`** is a class that maintains mutable state and dispatches notifications to subscribers via **`notifyListeners()`**:

```dart
// lib/features/cart/domain/cart_notifier.dart
import 'dart:collection';
import 'package:flutter/foundation.dart';

class CartItem {
  final String id;
  final String title;
  final double price;
  final int quantity;

  const CartItem({
    required this.id,
    required this.title,
    required this.price,
    this.quantity = 1,
  });

  CartItem copyWith({int? quantity}) {
    return CartItem(
      id: id,
      title: title,
      price: price,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartNotifier extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  // Expose unmodifiable view:
  UnmodifiableListView<CartItem> get items =>
      UnmodifiableListView(_items.values.toList());

  int get totalItemCount =>
      _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice =>
      _items.values.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  void addItem(String id, String title, double price) {
    if (_items.containsKey(id)) {
      _items[id] = _items[id]!.copyWith(quantity: _items[id]!.quantity + 1);
    } else {
      _items[id] = CartItem(id: id, title: title, price: price);
    }
    // Notify all listening widgets to trigger a rebuild!
    notifyListeners();
  }

  void removeItem(String id) {
    _items.remove(id);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
```

---

## 3. Registering Providers with `MultiProvider`

Mount your providers near the top of the widget tree so that all screens and modals have access:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'features/cart/domain/cart_notifier.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        // Instantiates and manages the lifecycle of CartNotifier:
        ChangeNotifierProvider(create: (_) => CartNotifier()),
      ],
      child: const MainApplication(),
    ),
  );
}

class MainApplication extends StatelessWidget {
  const MainApplication({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Provider Enterprise Store',
      theme: ThemeData.dark(),
      home: const CatalogHomeScreen(),
    );
  }
}
```

---

## 4. Consuming State: `context.watch`, `context.read` & `context.select`

There are three ways to access state from `BuildContext`:

```
┌─────────────────────────────────────────────────────────────┐
│                 Provider Context Access Modes               │
├────────────────────┬────────────────────────────────────────┤
│ **`context.watch<T>()`**  │ **Listens to all changes**.    │
│                           │ Rebuilds the widget whenever   │
│                           │ `notifyListeners()` is called. │
├────────────────────┼────────────────────────────────────────┤
│ **`context.read<T>()`**   │ **Reads without listening**.   │
│                           │ Never triggers rebuilds.       │
│                           │ Use inside `onPressed` handlers│
├────────────────────┼────────────────────────────────────────┤
│ **`context.select<T, R>()`│ **Fine-Grained Selection**.     │
│                           │ Rebuilds ONLY when the selected│
│                           │ field changes (e.g. count)!    │
└────────────────────┴────────────────────────────────────────┘
```

### 1. Fine-Grained Badge with `context.select`:

```dart
class CartBadgeIcon extends StatelessWidget {
  const CartBadgeIcon({super.key});

  @override
  Widget build(BuildContext context) {
    // ◄── REBUILDS ONLY WHEN totalItemCount CHANGES!
    // Adding/updating prices will NOT cause this badge to re-render!
    final count = context.select<CartNotifier, int>((cart) => cart.totalItemCount);

    return Badge(
      label: Text('$count'),
      isLabelVisible: count > 0,
      child: const Icon(Icons.shopping_cart),
    );
  }
}
```

### 2. Button Callback with `context.read`:

```dart
class AddToCartButton extends StatelessWidget {
  final String productId;
  final String title;
  final double price;

  const AddToCartButton({
    super.key,
    required this.productId,
    required this.title,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      // Use context.read inside event callbacks!
      onPressed: () {
        context.read<CartNotifier>().addItem(productId, title, price);
      },
      child: const Text('Add to Cart'),
    );
  }
}
```

---

## 5. The `Consumer<T>` & `Selector<T, S>` Widgets

If you want to scope the rebuild to a tiny part of a large widget tree without splitting into a new class:

```dart
class CartSummaryCard extends StatelessWidget {
  const CartSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Checkout Breakdown (Static Header)'),
            const Divider(),
            // Only this Consumer block rebuilds when cart updates:
            Consumer<CartNotifier>(
              builder: (context, cart, child) {
                return Text(
                  'Total: \$${cart.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Troubleshooting & Best Practices

1. **`Tried to listen to a value exposed with provider outside of the widget tree`**
   This happens if you call `context.read()` or `context.watch()` above the `ChangeNotifierProvider` in the same `build()` method. The provider must be created in an ancestor widget above the widget that reads it.

2. **Never Call `context.watch()` inside `onPressed` or Event Handlers**
   Calling `context.watch()` inside an event handler throws a runtime error. Always use `context.read<T>()` inside callbacks.
