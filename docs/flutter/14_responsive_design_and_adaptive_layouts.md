# Module 14: Responsive & Adaptive Design for Multi-Platform Flutter

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** Multi-Platform UX, Responsive Breakpoints & Adaptive Controls

---

## 1. Responsive vs Adaptive Architecture in Flutter

Developing for multi-platform (Mobile, Web, macOS, Windows, Linux) requires mastering two distinct dimensions:

```text
┌─────────────────────────────────────────────────────────────┐
│                 Responsive vs Adaptive Design               │
├────────────────────┬────────────────────────────────────────┤
│ **Responsive**     │ **Adapts to SCREEN GEOMETRY**          │
│                    │ - Screen width, height, aspect ratio.  │
│                    │ - Layout shifts (1-column mobile to    │
│                    │   3-column desktop dashboard).         │
│                    │ - `LayoutBuilder`, `MediaQuery`.       │
├────────────────────┼────────────────────────────────────────┤
│ **Adaptive**       │ **Adapts to PLATFORM & INPUT DEVICES** │
│                    │ - Touch vs Mouse Hover & Right-Click.  │
│                    │ - Keyboard navigation & shortcuts.     │
│                    │ - Material 3 vs Apple Cupertino design.│
│                    │ - Window resizing & menu bars.         │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. The Responsive Breakpoint Engine

```dart
// lib/core/responsive/responsive_layout.dart
import 'package:flutter/material.dart';

enum DeviceScreenType { mobile, tablet, desktop }

class Breakpoints {
  static const double mobileMax = 600.0;
  static const double tabletMax = 1024.0;

  static DeviceScreenType getDeviceType(double width) {
    if (width < mobileMax) return DeviceScreenType.mobile;
    if (width < tabletMax) return DeviceScreenType.tablet;
    return DeviceScreenType.desktop;
  }
}

class ResponsiveLayoutBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) mobile;
  final Widget Function(BuildContext context)? tablet;
  final Widget Function(BuildContext context) desktop;

  const ResponsiveLayoutBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenType = Breakpoints.getDeviceType(constraints.maxWidth);

        switch (screenType) {
          case DeviceScreenType.desktop:
            return desktop(context);
          case DeviceScreenType.tablet:
            return (tablet ?? desktop)(context);
          case DeviceScreenType.mobile:
            return mobile(context);
        }
      },
    );
  }
}
```

---

## 3. Keyboard Insets & Safe Area Management (`MediaQuery`)

Handling the on-screen virtual keyboard without overflowing UI widgets:

```dart
class KeyboardAwareFormView extends StatelessWidget {
  const KeyboardAwareFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return Scaffold(
      // Automatically resizes body when keyboard slides up:
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            // Add extra bottom padding when keyboard opens:
            bottom: mediaQuery.viewInsets.bottom + 24,
          ),
          child: Column(
            children: [
              const Text('Secure Authentication'),
              const TextField(decoration: InputDecoration(labelText: 'Email')),
              const TextField(decoration: InputDecoration(labelText: 'Password')),
              if (!isKeyboardOpen) ...[
                const SizedBox(height: 40),
                const Text('Company Legal Terms & Privacy Notice'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 4. Adaptive Platform Widgets & Dialogs

Render native Cupertino controls on iOS/macOS and Material 3 controls on Android/Windows/Web:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AdaptiveControlsDemo extends StatefulWidget {
  const AdaptiveControlsDemo({super.key});

  @override
  State<AdaptiveControlsDemo> createState() => _AdaptiveControlsDemoState();
}

class _AdaptiveControlsDemoState extends State<AdaptiveControlsDemo> {
  bool _switchVal = true;
  double _sliderVal = 0.5;

  void _showAdaptiveConfirmDialog(BuildContext context) {
    showAdaptiveDialog(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Confirm Action'),
        content: const Text('Do you want to apply system changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Adaptive Switch (CupertinoSwitch on iOS, Material Switch on Android)
        Switch.adaptive(
          value: _switchVal,
          onChanged: (v) => setState(() => _switchVal = v),
        ),

        // 2. Adaptive Slider
        Slider.adaptive(
          value: _sliderVal,
          onChanged: (v) => setState(() => _sliderVal = v),
        ),

        ElevatedButton(
          onPressed: () => _showAdaptiveConfirmDialog(context),
          child: const Text('Open Adaptive Dialog'),
        ),
      ],
    );
  }
}
```

---

## 5. Desktop & Web Ergonomics: Mouse Regions & Keyboard Shortcuts

Desktop and Web users expect hover effects, right-click context menus, and keyboard shortcuts (`Ctrl+S` / `Cmd+S`):

```dart
// lib/features/desktop/desktop_shortcut_wrapper.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 1. Custom Intent for Save Action:
class SaveIntent extends Intent {
  const SaveIntent();
}

class DesktopInteractiveCard extends StatefulWidget {
  final VoidCallback onSave;
  const DesktopInteractiveCard({super.key, required this.onSave});

  @override
  State<DesktopInteractiveCard> createState() => _DesktopInteractiveCardState();
}

class _DesktopInteractiveCardState extends State<DesktopInteractiveCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      // 2. Register Keyboard Shortcuts (Cmd+S on Mac, Ctrl+S on Windows/Linux):
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS): const SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): const SaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (intent) {
              widget.onSave();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: MouseRegion(
            // 3. Track Mouse Hover & Cursor Styling:
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isHovered ? const Color(0xFF334155) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isHovered ? Colors.indigoAccent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: const Text('Hover or Press Cmd+S / Ctrl+S to Save'),
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## Troubleshooting & Best Practices

1. **`MediaQuery.of(context)` vs `MediaQuery.sizeOf(context)`**
   In Flutter 3.10+, always use `MediaQuery.sizeOf(context)` or `MediaQuery.orientationOf(context)` instead of `MediaQuery.of(context)`. The granular methods ensure your widget re-renders **only when the specific property changes**, rather than on every keyboard animation tick.

2. **Always Wrap Root Layout in `SelectionArea` on Web/Desktop**
   On Web and Desktop, users expect to select and copy text using mouse drag. Wrap your `Scaffold` body in `SelectionArea(child: ...)` to enable native text selection.
