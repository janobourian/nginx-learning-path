# Module 02: Stateless vs Stateful Widgets & The Complete `State` Lifecycle

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine  
**Category:** Component Lifecycles, State Transitions & Memory Cleanup

---

## 1. `StatelessWidget` vs `StatefulWidget`

In Flutter, UI components inherit from either `StatelessWidget` or `StatefulWidget`:

```
┌─────────────────────────────────────────────────────────────┐
│              Widget Class Architecture Comparison           │
├──────────────────────────┬──────────────────────────────────┤
│ **`StatelessWidget`**    │ **Pure & Immutable**             │
│                          │ - Has no mutable internal state. │
│                          │ - Rebuilds only when parent      │
│                          │   passes new constructor props or│
│                          │   InheritedWidget changes.       │
├──────────────────────────┼──────────────────────────────────┤
│ **`StatefulWidget`**     │ **Mutable & Persistent**         │
│                          │ - Delegates state to a long-lived│
│                          │   `State<T>` object in the       │
│                          │   Element Tree.                  │
│                          │ - Can mutate state and trigger   │
│                          │   rebuilds via `setState()`.     │
└──────────────────────────┴──────────────────────────────────┘
```

---

## 2. The Complete `State` Lifecycle Sequence

The lifecycle of a `State<T>` object moves through an exact sequence of lifecycle stages:

```
┌─────────────────────────────────────────────────────────────┐
│                 The Complete State Lifecycle                │
│                                                             │
│  [1. createState()] ──────────► Instantiates State object   │
│            │                                                │
│  [2. initState()] ────────────► One-time initialization     │
│            │                                                │
│  [3. didChangeDependencies()] ─► InheritedWidgets resolve   │
│            │                                                │
│  [4. build()] ◄──────────────┐  Renders Widget Tree         │
│            │                 │                              │
│            ├─► [setState()] ─┘  (Re-queues build())         │
│            │                                                │
│            ├─► [didUpdateWidget()] (Parent passed new props)│
│            │                                                │
│  [5. deactivate()] ───────────► Temporarily unmounted       │
│            │                                                │
│  [6. dispose()] ──────────────► Permanent destruction & GC  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Deep Dive into Lifecycle Methods

| Lifecycle Method | When It Runs | What To Do Inside | What NEVER To Do |
| :--- | :--- | :--- | :--- |
| **`initState()`** | **Once** upon creation | Subscribe to Streams, initialize `TextEditingController`, `AnimationController` | Do NOT access `BuildContext` inherited widgets (Theme/MediaQuery) |
| **`didChangeDependencies()`** | Right after `initState` and whenever `InheritedWidget` updates | Read `Theme.of(context)`, `MediaQuery.of(context)`, `Provider.of(context)` | Avoid expensive computations |
| **`build()`** | Every time state changes or parent rebuilds | Return pure Widget subtree | **NEVER trigger HTTP calls or `setState()`** |
| **`didUpdateWidget()`** | When parent rebuilds with new props | Compare `oldWidget.property != widget.property` and update controllers | Avoid resetting state unnecessarily |
| **`dispose()`** | When widget is removed permanently | Call `.dispose()` on all controllers, cancel all `StreamSubscription` | **NEVER call `setState()`** |

---

## 4. Production Master Example: Lifecycle-Safe Search Widget

Here is an enterprise implementation managing an `AnimationController`, a `TextEditingController`, and handling `didUpdateWidget` and `mounted` checks safely:

```dart
// lib/features/search/presentation/widgets/lifecycle_search_bar.dart
import 'dart:async';
import 'package:flutter/material.dart';

class LifecycleSearchBar extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onSearchSubmitted;
  final bool isExpanded;

  const LifecycleSearchBar({
    super.key,
    this.initialQuery = '',
    required this.onSearchSubmitted,
    this.isExpanded = false,
  });

  @override
  State<LifecycleSearchBar> createState() => _LifecycleSearchBarState();
}

class _LifecycleSearchBarState extends State<LifecycleSearchBar>
    with SingleTickerProviderStateMixin {
  // 1. Controllers & Subscriptions managed by this State:
  late final TextEditingController _textController;
  late final AnimationController _animationController;
  late final Animation<double> _expandAnimation;
  Timer? _debounceTimer;

  // 2. ONE-TIME INITIALIZATION:
  @override
  void initState() {
    super.initState();
    print('[Lifecycle]: initState called');

    _textController = TextEditingController(text: widget.initialQuery);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    if (widget.isExpanded) {
      _animationController.value = 1.0;
    }
  }

  // 3. INHERITED WIDGET DEPENDENCY TRACKING:
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('[Lifecycle]: didChangeDependencies called (Theme/Locale ready)');
  }

  // 4. PARENT WIDGET CONFIGURATION UPDATES:
  @override
  void didUpdateWidget(covariant LifecycleSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('[Lifecycle]: didUpdateWidget called');

    // If parent passed a different expanded state, animate smoothly:
    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }

    // If parent programmatically changed initial query:
    if (oldWidget.initialQuery != widget.initialQuery &&
        _textController.text != widget.initialQuery) {
      _textController.text = widget.initialQuery;
    }
  }

  void _onTextChanged(String newText) {
    // Debounce keystrokes by 400ms:
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      // 5. CRITICAL: Always check 'mounted' before calling setState after async delay!
      if (!mounted) return;

      widget.onSearchSubmitted(newText);
    });
  }

  // 6. BUILD METHOD (Pure Render):
  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _expandAnimation,
      axisAlignment: -1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
        ),
        child: TextField(
          controller: _textController,
          onChanged: _onTextChanged,
          decoration: const InputDecoration(
            hintText: 'Search enterprise directory...',
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // 7. PERMANENT TEARDOWN & CLEANUP:
  @override
  void dispose() {
    print('[Lifecycle]: dispose called. Releasing resources.');

    // Cancel active background timers:
    _debounceTimer?.cancel();

    // Dispose all controllers to prevent memory leaks:
    _textController.dispose();
    _animationController.dispose();

    super.dispose();
  }
}
```

---

## Troubleshooting & Best Practices

1. **`setState() called after dispose()` Crash**
   If an asynchronous operation (`await fetch()`) completes after a user has navigated away and the widget was unmounted, calling `setState()` will throw an unhandled `FlutterError`. Always wrap async `setState()` calls in **`if (mounted) { setState(...) }`**.

2. **Never Call `dispose()` on Injected / Inherited Controllers**
   Only call `.dispose()` on controllers that were **instantiated directly inside this State's `initState()`**. If a controller was passed down from a parent or injected via Provider/Riverpod, the parent is responsible for its disposal.
