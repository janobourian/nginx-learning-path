# Module 17: Automated Testing — Widget Tests, Golden Toolkit & Integration Tests

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine  
**Category:** Automated Testing, WidgetTester & Pixel-Perfect Golden Testing

---

## 1. The Flutter Automated Testing Pyramid

Flutter provides a comprehensive, built-in testing suite covering three distinct testing levels:

```
┌─────────────────────────────────────────────────────────────┐
│                 The Flutter Testing Pyramid                 │
├────────────────────┬────────────────────────────────────────┤
│ **1. Integration** │ **Real Devices & Emulators**           │
│    **Tests**       │ - Tests entire app end-to-end.         │
│                    │ - Runs on actual iOS/Android runtimes. │
├────────────────────┼────────────────────────────────────────┤
│ **2. Golden Tests**│ **Pixel-Perfect Visual Regression**    │
│                    │ - Compares rendered canvas frames      │
│                    │   against reference PNG screenshots.   │
├────────────────────┼────────────────────────────────────────┤
│ **3. Widget Tests**│ **Component Behavior & Interactions**  │
│                    │ - Runs in headless simulated UI.       │
│                    │ - Ultra-fast (~100ms per test).        │
├────────────────────┼────────────────────────────────────────┤
│ **4. Unit Tests**  │ **Pure Business Logic**                │
│                    │ - BLoCs, Repositories, Data Models.    │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Widget Testing with `WidgetTester`

Widget tests mount a component inside a simulated headless Flutter test environment, allowing you to simulate taps, scrolling, and verify DOM text without launching a simulator:

```dart
// test/widget/login_form_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Component to test:
class LoginFormWidget extends StatefulWidget {
  final ValueChanged<String> onLogin;
  const LoginFormWidget({super.key, required this.onLogin});

  @override
  State<LoginFormWidget> createState() => _LoginFormWidgetState();
}

class _LoginFormWidgetState extends State<LoginFormWidget> {
  final _emailController = TextEditingController();
  bool _hasError = false;

  void _submit() {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
      setState(() => _hasError = true);
    } else {
      setState(() => _hasError = false);
      widget.onLogin(_emailController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          key: const Key('email_field'),
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        if (_hasError)
          const Text('Invalid email format', style: TextStyle(color: Colors.red)),
        ElevatedButton(
          key: const Key('login_button'),
          onPressed: _submit,
          child: const Text('Sign In'),
        ),
      ],
    );
  }
}

void main() {
  group('LoginFormWidget Tests', () {
    testWidgets('shows validation error when email is invalid', (WidgetTester tester) async {
      // 1. Pump the widget inside a MaterialApp wrapper:
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoginFormWidget(onLogin: (email) {}),
          ),
        ),
      );

      // 2. Find widgets using Finders:
      final emailFieldFinder = find.byKey(const Key('email_field'));
      final loginButtonFinder = find.byKey(const Key('login_button'));

      // 3. Simulate typing invalid text:
      await tester.enterText(emailFieldFinder, 'invalid-email-string');

      // 4. Tap the submit button:
      await tester.tap(loginButtonFinder);

      // 5. Trigger frame rebuild:
      await tester.pump();

      // 6. Assertions:
      expect(find.text('Invalid email format'), findsOneWidget);
    });

    testWidgets('calls onLogin callback when valid email is submitted', (WidgetTester tester) async {
      String? submittedEmail;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoginFormWidget(
              onLogin: (email) => submittedEmail = email,
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('email_field')), 'alice@acme.com');
      await tester.tap(find.byKey(const Key('login_button')));

      // pumpAndSettle waits for all animations/timers to complete:
      await tester.pumpAndSettle();

      expect(submittedEmail, equals('alice@acme.com'));
      expect(find.text('Invalid email format'), findsNothing);
    });
  });
}
```

---

## 3. Understanding `tester.pump()` vs `tester.pumpAndSettle()`

- **`tester.pump()`**: Traces a single frame tick (e.g. immediately after `setState()`).
- **`tester.pumpAndSettle()`**: Repeatedly calls `pump()` until there are **no outstanding microtasks, animation tickers, or scheduled timers left in the event queue**.

---

## 4. Pixel-Perfect Golden Regression Tests

**Golden Tests** render a widget and compare its exact pixel output against a reference `.png` image:

```dart
// test/golden/user_card_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('UserCard golden visual regression test', (WidgetTester tester) async {
    // Set custom screen resolution (e.g. iPhone 14 Pro dimensions):
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Enterprise Golden Target'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify rendered pixels match the reference PNG file:
    await expectLater(
      find.byType(Card),
      matchesGoldenFile('goldens/user_card_master.png'),
    );
  });
}
```

### Generating Master Golden PNG Images:

```bash
# Generate reference baseline images:
flutter test --update-goldens
```

---

## 5. End-to-End Integration Testing (`integration_test`)

Integration tests run on real iOS/Android devices and verify native platform interactions:

```yaml
# pubspec.yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

```dart
// integration_test/app_flow_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_flutter_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Complete end-to-end checkout flow', (WidgetTester tester) async {
    // 1. Launch real app:
    app.main();
    await tester.pumpAndSettle();

    // 2. Tap navigation button:
    final catalogButton = find.text('Browse Catalog');
    expect(catalogButton, findsOneWidget);
    await tester.tap(catalogButton);
    await tester.pumpAndSettle();

    // 3. Add first product to cart:
    await tester.tap(find.text('Add to Cart').first);
    await tester.pumpAndSettle();

    // 4. Verify checkout total:
    expect(find.text('Cart Total: \$149.99'), findsOneWidget);
  });
}
```

Run integration test:
```bash
flutter test integration_test/app_flow_test.dart -d macos
```

---

## Troubleshooting & Best Practices

1. **`pumpAndSettle timed out` Warning**
   If `pumpAndSettle()` times out, your widget contains an infinite animation (e.g. `AnimationController.repeat()` or a continuous `CircularProgressIndicator`). Use `tester.pump(const Duration(milliseconds: 100))` with explicit durations instead of `pumpAndSettle()`.

2. **Cross-Platform Golden Font Rendering**
   Golden test rasterization can vary slightly across macOS and Linux CI runners due to font smoothing. Use packages like `golden_toolkit` to load consistent mock fonts during tests.
