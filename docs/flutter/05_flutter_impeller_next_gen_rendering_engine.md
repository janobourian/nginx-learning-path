# Module 05: Impeller — Next-Generation Rendering Engine & Custom GLSL Shaders

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** GPU Architecture, Graphics Shaders & Impeller Rendering Pipeline

---

## 1. What Is Impeller and Why Was Skia Replaced?

For years, Flutter used **Skia** (the 2D graphics engine that also powers Google Chrome and Android OS).

While Skia is a capable general-purpose 2D library, it caused a major issue in Flutter mobile applications: **Shader Compilation Jank**.

### The Root Cause of Shader Compilation Jank in Skia

- When an app displayed a new visual effect for the very first time (e.g. a blurred bottom navigation bar, a clip shadow, or a gradient swipe), Skia had to compile the corresponding GPU shader program **Just-In-Time (JIT) on the main UI raster thread**.
- Compiling a shader on a mobile GPU takes **20ms to 100ms+**.
- Because an 8.3ms (120fps) or 16.6ms (60fps) frame budget was exceeded, the UI visibly froze and dropped frames (jank) during the user's initial interaction.

### How Impeller Eliminates Shader Jank Completely

**Impeller** is Flutter's ground-up rewrite of the 2D rendering engine:

1. **Ahead-Of-Time (AOT) Shader Compilation**: All shaders are pre-compiled at **application build time** into native **Metal Shading Language (MSL)** on iOS/macOS and **SPIR-V / Vulkan shaders** on Android.
2. **Predictable Frame Pacing**: Because shaders are pre-compiled, the GPU executes draw calls with **zero runtime compilation pauses**, guaranteeing smooth 60fps/120fps animations from the very first frame.
3. **Designed for Modern Explicit GPU APIs**: Built specifically for **Apple Metal** and **Khronos Vulkan**, leveraging modern multi-threaded command encoding.

```text
Rendering Pipeline Comparison:

Skia (JIT Shader Compilation on First Draw):
[User opens screen] ──► [Draw blur effect] ──► [Compiles Shader JIT (50ms) 💥 JANK!] ──► Frame painted

Impeller (AOT Pre-Compiled Shaders):
[Application Build Time] ──► Pre-compiles all shaders to MSL / SPIR-V
[User opens screen]       ──► [Draw blur effect] ──► [Instant GPU execution (<2ms) ✅ SMOOTH!]
```

---

## 2. The Internal Architecture of Impeller

Impeller is structured into a clean pipeline:

```text
┌─────────────────────────────────────────────────────────────┐
│                 Impeller Graphics Pipeline                  │
│                                                             │
│  [1. DisplayList] ────────► Records canvas commands from    │
│            │                Dart Framework RenderObjects    │
│            ▼                                                │
│  [2. Aiks (Entity Pass)] ─► High-level 2D geometry, clips,  │
│            │                and blend modes                 │
│            ▼                                                │
│  [3. Content / Tessellation] Breaks complex paths into      │
│            │                 triangles for GPU vertex pipes │
│            ▼                                                │
│  [4. HAL (Hardware Abstraction Layer)]                      │
│      ├── Metal Driver Backend (iOS, macOS)                  │
│      ├── Vulkan Driver Backend (Android, Linux)             │
│      └── WebGPU / OpenGLES Fallback                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Performance Benchmarks: Impeller vs Skia

In real-world e-commerce and social feed benchmarks (scrolling complex lists with hero transitions, blur filters, and shadows):

| Metric | Skia (Legacy Engine) | Impeller (Modern Engine) |
| :--- | :--- | :--- |
| **First-Run Animation Jank** | **Severe (30–60ms frame spikes)** | **Zero (0 dropped frames)** |
| **99th Percentile Frame Time** | ~24.5 ms | **~6.8 ms (Stable 120fps)** |
| **GPU Memory Footprint** | Dynamic allocation spikes | **Predictable bounded buffers** |
| **API Backend** | Legacy OpenGL / Metal wrapper | **Native Metal / Vulkan** |

---

## 4. Custom GLSL Fragment Shaders in Flutter (`ui.FragmentProgram`)

Impeller makes writing and loading custom **GLSL Fragment Shaders** seamless and hardware-accelerated:

### 1. Writing a GLSL Shader (`shaders/ripple.frag`)

```glsl
// shaders/ripple.frag

#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uTouchCenter;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    vec2 center = uTouchCenter / uResolution;

    float dist = distance(uv, center);
    float wave = sin(dist * 30.0 - uTime * 4.0) * 0.03;

    vec2 distortedUv = uv + (uv - center) * wave;

    // Glowing cyan/indigo ripple pattern:
    vec3 color = vec3(0.1, 0.4, 0.9) + sin(dist * 20.0 - uTime * 2.0) * 0.2;
    fragColor = vec4(color, 1.0);
}
```

### 2. Registering the Shader in `pubspec.yaml`

```yaml
flutter:
  shaders:

    - shaders/ripple.frag
```

---

## 5. Executing Custom Shaders in Flutter Dart Code

```dart
// lib/features/graphics/shader_widget.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class RippleShaderWidget extends StatefulWidget {
  const RippleShaderWidget({super.key});

  @override
  State<RippleShaderWidget> createState() => _RippleShaderWidgetState();
}

class _RippleShaderWidgetState extends State<RippleShaderWidget>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final AnimationController _ticker;
  Offset _touchPosition = const Offset(150, 150);

  @override
  void initState() {
    super.initState();
    _loadShader();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  Future<void> _loadShader() async {
    // Asynchronously load the pre-compiled AOT shader program:
    final program = await ui.FragmentProgram.fromAsset('shaders/ripple.frag');
    setState(() {
      _shader = program.fragmentShader();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _touchPosition = details.localPosition;
        });
      },
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(double.infinity, 400),
            painter: _ShaderPainter(
              shader: _shader!,
              time: _ticker.value * 10.0,
              touch: _touchPosition,
            ),
          );
        },
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final Offset touch;

  _ShaderPainter({required this.shader, required this.time, required this.touch});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Pass Uniform values to the GLSL shader:
    shader.setFloat(0, size.width);       // uResolution.x
    shader.setFloat(1, size.height);      // uResolution.y
    shader.setFloat(2, time);             // uTime
    shader.setFloat(3, touch.dx);         // uTouchCenter.x
    shader.setFloat(4, touch.dy);         // uTouchCenter.y

    // 2. Paint shader directly onto canvas:
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter oldDelegate) => true;
}
```

---

## Troubleshooting & Best Practices

1. **Verify Impeller is Enabled on Your Target Device**
   Impeller is enabled by default on iOS, macOS, and modern Android devices. To explicitly verify or toggle Impeller via CLI:

   ```bash
   flutter run --enable-impeller
   ```

2. **Always Dispose `ui.FragmentShader`**
   When using custom GLSL shaders, invoke `shader.dispose()` in your State's `dispose()` method to release native GPU memory buffers immediately.
