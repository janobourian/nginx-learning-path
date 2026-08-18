# Module 04: Low-Level 2D Graphics with `CustomPaint`, `CustomPainter` & `Canvas`

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine  
**Category:** 2D Graphics, Canvas Rendering & Shader Shading

---

## 1. What Is `CustomPainter`?

When standard Flutter widgets (`Container`, `Card`, `DecoratedBox`) cannot express custom geometric shapes, data visualizations, circular dials, or particle effects, **`CustomPaint`** and **`CustomPainter`** give you direct, raw access to the low-level 2D GPU **`Canvas`**.

```
CustomPainter Pipeline:
[CustomPaint Widget]
        │
        ▼ passes Canvas & Size to:
[CustomPainter.paint(Canvas canvas, Size size)]
        │
        ├── 1. Configure Paint (Colors, Gradients, Stroke Width, Shaders)
        ├── 2. Build Geometric Paths (Bezier curves, arcs, lines)
        └── 3. Submit Draw Calls (drawCircle, drawPath, drawPoints) ──► GPU!
```

---

## 2. Anatomy of a `CustomPainter`

```dart
class MyCustomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Drawing logic executed here on each repaint frame
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // 2. Return true ONLY when painter properties change to skip redundant repaints!
    return false;
  }
}
```

---

## 3. The `Canvas` and `Paint` API Matrix

### The `Paint` Object (Brush Configuration):

| Property | Description | Example |
| :--- | :--- | :--- |
| **`style`** | `PaintingStyle.stroke` (Outline) vs `PaintingStyle.fill` (Filled shape) | `paint.style = PaintingStyle.stroke;` |
| **`strokeWidth`** | Thickness of stroke in logical pixels | `paint.strokeWidth = 6.0;` |
| **`strokeCap`** | Round, Butt, or Square line endings | `paint.strokeCap = StrokeCap.round;` |
| **`shader`** | Gradients (`Gradient.linear`, `Gradient.sweep`) | `paint.shader = gradient.createShader(rect);` |
| **`maskFilter`** | GPU blur filters for drop shadows and glows | `paint.maskFilter = MaskFilter.blur(BlurStyle.normal, 8);` |

### Core `Canvas` Draw Operations:
- **`canvas.drawLine(p1, p2, paint)`**
- **`canvas.drawCircle(center, radius, paint)`**
- **`canvas.drawRRect(rrect, paint)`** (Rounded rectangle)
- **`canvas.drawArc(rect, startAngle, sweepAngle, useCenter, paint)`**
- **`canvas.drawPath(path, paint)`** (Complex Bezier paths)

---

## 4. Production Master Example: Animated Gradient Circular Gauge

Let's build a glowing, gradient circular progress gauge with smooth sweep angles:

```dart
// lib/shared/widgets/circular_progress_gauge.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class CircularProgressGauge extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final double strokeWidth;
  final List<Color> gradientColors;

  const CircularProgressGauge({
    super.key,
    required this.progress,
    this.strokeWidth = 14.0,
    this.gradientColors = const [Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFFF59E0B)],
  }) : assert(progress >= 0.0 && progress <= 1.0, 'Progress must be between 0.0 and 1.0');

  @override
  State<CircularProgressGauge> createState() => _CircularProgressGaugeState();
}

class _CircularProgressGaugeState extends State<CircularProgressGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _oldProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<double>(begin: 0.0, end: widget.progress).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant CircularProgressGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _oldProgress = oldWidget.progress;
      _animation = Tween<double>(begin: _oldProgress, end: widget.progress).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(200, 200),
          painter: _GaugePainter(
            progress: _animation.value,
            strokeWidth: widget.strokeWidth,
            gradientColors: widget.gradientColors,
          ),
          child: SizedBox(
            width: 200,
            height: 200,
            child: Center(
              child: Text(
                '${(_animation.value * 100).toInt()}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final List<Color> gradientColors;

  _GaugePainter({
    required this.progress,
    required this.strokeWidth,
    required this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Draw Background Track Ring:
    final trackPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.0) return;

    // 2. Draw Glowing Drop Shadow:
    final glowPaint = Paint()
      ..color = gradientColors.first.withOpacity(0.4)
      ..strokeWidth = strokeWidth + 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    const startAngle = -math.pi / 2; // Top of circle (12 o'clock)
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);

    // 3. Draw Gradient Progress Ring:
    final gradient = SweepGradient(
      startAngle: 0.0,
      endAngle: 2 * math.pi,
      colors: gradientColors,
      transform: const GradientRotation(-math.pi / 2),
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gradientColors != gradientColors;
  }
}
```

---

## 5. Custom Hit Testing (`hitTest()`)

If your `CustomPainter` needs to respond to pointer taps inside a specific non-rectangular geometric shape:

```dart
class InteractiveShapePainter extends CustomPainter {
  final Path customShapePath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    customShapePath.reset();
    customShapePath.addOval(Rect.fromLTWH(20, 20, size.width - 40, size.height - 40));
    canvas.drawPath(customShapePath, Paint()..color = Colors.blue);
  }

  @override
  bool hitTest(Offset position) {
    // Returns true ONLY if the user tapped INSIDE the custom path geometry!
    return customShapePath.contains(position);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

---

## Troubleshooting & Best Practices

1. **Avoid Allocating `Paint()` Objects Inside `paint()`**
   If you have a static paint configuration, instantiate the `Paint` object as a field or reuse it rather than calling `Paint()` hundreds of times per second inside the hot `paint()` loop.

2. **Always Implement `shouldRepaint()` Accurately**
   Returning `true` unconditionally from `shouldRepaint()` forces Flutter to repaint the custom canvas on every single frame tick, even if the parent widget was simply animating unrelated opacity. Compare old and new properties to return `false` when data is unchanged.
