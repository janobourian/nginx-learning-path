# Module 07: Explicit Animations — Controllers, Tweens & Staggered Curves

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine  
**Category:** Animation Engineering, Tickers, Tweens & Staggered Motion

---

## 1. The Explicit Animation Architecture

Flutter provides two animation systems:
1. **Implicit Animations** (Module 08): Simple, automated transitions (`AnimatedContainer`, `AnimatedOpacity`).
2. **Explicit Animations** (This Module): Fine-grained programmatic control over complex, multi-stage, repeating, reversible, or staggered animations.

```
Explicit Animation Pipeline:
┌─────────────────────────────────────────────────────────────┐
│ 1. TickerProvider (VSync)                                    │
│    - Synchronizes ticks with display hardware refresh rate   │
│      (e.g. exactly 120 ticks/sec on ProMotion displays).     │
│                                                             │
│ 2. AnimationController (0.0 to 1.0 Timeline)                │
│    - Controls time, duration, playback direction & status.  │
│                                                             │
│ 3. CurvedAnimation (Interpolation Easing Curve)             │
│    - Transforms linear 0.0–1.0 into non-linear curve         │
│      (e.g. Curves.elasticOut, Curves.easeOutCubic).         │
│                                                             │
│ 4. Tween<T> (Data Range Transformation)                     │
│    - Maps 0.0–1.0 into concrete types                       │
│      (e.g. 0.0..1.0 ──► Color(Red)..Color(Blue)).           │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Setting Up an `AnimationController`

To create an `AnimationController`, mix in **`SingleTickerProviderStateMixin`**:

```dart
class _MyAnimationState extends State<MyWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Initialize Controller:
    _controller = AnimationController(
      vsync: this, // Tells controller to tick only when screen is active
      duration: const Duration(milliseconds: 800),
    );

    // 2. Curved Easing:
    final curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    // 3. Tweens:
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(curvedAnimation);

    _colorAnimation = ColorTween(
      begin: const Color(0xFF6366F1),
      end: const Color(0xFFEC4899),
    ).animate(curvedAnimation);

    // 4. Play Animation:
    _controller.forward();
  }

  @override
  void dispose() {
    // Crucial: Dispose controller to cancel VSync Ticker!
    _controller.dispose();
    super.dispose();
  }
}
```

---

## 3. Controlling Animation Playback & Status

An `AnimationController` exposes rich playback methods and lifecycle status listeners:

```dart
// Playback Commands:
_controller.forward();           // Plays 0.0 -> 1.0
_controller.reverse();           // Plays 1.0 -> 0.0
_controller.repeat(reverse: true); // Continuous ping-pong loop!
_controller.reset();             // Sets value back to 0.0

// Status Listeners:
_controller.addStatusListener((AnimationStatus status) {
  switch (status) {
    case AnimationStatus.completed:
      print('Animation finished. Reversing...');
      _controller.reverse();
    case AnimationStatus.dismissed:
      print('Animation returned to beginning (0.0).');
    case AnimationStatus.forward:
      print('Playing forward...');
    case AnimationStatus.reverse:
      print('Playing in reverse...');
  }
});
```

---

## 4. Staggered Animations (Interval Sequences)

A **Staggered Animation** coordinates multiple animated visual changes (e.g. an element slides in, then expands, then changes color, then fades out) across a single unified `AnimationController` timeline using **`Interval`**:

```
Staggered Animation Timeline (Total Duration: 2,000ms):
[0.0 ──────────── 0.4] ◄── 1. Opacity Fade In (Interval 0.0 to 0.4)
        [0.2 ──────────── 0.7] ◄── 2. Slide Y Translation (Interval 0.2 to 0.7)
                [0.5 ──────────── 1.0] ◄── 3. Width Expansion (Interval 0.5 to 1.0)
```

```dart
// lib/features/animations/staggered_card.dart
import 'package:flutter/material.dart';

class StaggeredCardAnimation extends StatefulWidget {
  const StaggeredCardAnimation({super.key});

  @override
  State<StaggeredCardAnimation> createState() => _StaggeredCardAnimationState();
}

class _StaggeredCardAnimationState extends State<StaggeredCardAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Staggered Sub-Animations:
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _width;
  late final Animation<BorderRadius?> _borderRadius;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 1. Opacity Animation (First 30% of timeline):
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    // 2. Slide Translation Animation (From 20% to 60% of timeline):
    _slide = Tween<Offset>(
      begin: const Offset(0.0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // 3. Width Expansion (From 50% to 90% of timeline):
    _width = Tween<double>(begin: 100.0, end: 320.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 0.9, curve: Curves.easeInOut),
      ),
    );

    // 4. Border Radius (From 70% to 100% of timeline):
    _borderRadius = BorderRadiusTween(
      begin: BorderRadius.circular(50.0),
      end: BorderRadius.circular(16.0),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacity.value,
            child: SlideTransition(
              position: _slide,
              child: Container(
                width: _width.value,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                  ),
                  borderRadius: _borderRadius.value,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'Staggered Motion Card',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

---

## Troubleshooting & Best Practices

1. **`TickerCanceled` Exceptions**
   When `_controller.forward()` is running and the widget is disposed, the ticker cancels, which can throw a `TickerCanceled` error if unhandled. Always use `_controller.forward().orCancel` or catch `TickerCanceled`.

2. **Always Use `SingleTickerProviderStateMixin` for Single Controllers**
   Use `SingleTickerProviderStateMixin` when a State class manages exactly one `AnimationController`. If managing two or more concurrent controllers in the same State class, use `TickerProviderStateMixin`.
