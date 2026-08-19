# Module 18: Unit Testing, Mocking & Test Suites with `package:test`

**Track:** Dart — Language & VM Architecture
**Category:** Testing Architecture, Mocking & Code Coverage

---

## 1. The Official Dart Testing Framework (`package:test`)

Dart features a built-in, highly optimized test runner provided by **`package:test`**:

```yaml

# pubspec.yaml
dev_dependencies:
  test: ^1.25.2
  mocktail: ^1.0.3 # Modern mocking without build_runner code generation!
```

Run tests from the CLI:

```bash

# Run all tests in test/ directory
dart test

# Run tests in parallel across all CPU cores
dart test --concurrency=8

# Run only tests matching a name pattern
dart test --name "validation"

# Run tests with code coverage output
dart test --coverage=coverage
```

---

## 2. Test Structure & Matchers

```dart
// test/unit/pricing_calculator_test.dart
import 'package:test/test.dart';

class PricingCalculator {
  double calculateTax(double amount, double rate) {
    if (amount < 0 || rate < 0) {
      throw ArgumentError('Amount and rate must be non-negative.');
    }
    return double.parse((amount * rate).toStringAsFixed(2));
  }

  Future<double> fetchDiscountedPrice(double originalPrice) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return originalPrice * 0.9;
  }
}

void main() {
  late PricingCalculator calculator;

  // Setup hook executed before each test:
  setUp(() {
    calculator = PricingCalculator();
  });

  // Teardown hook executed after each test:
  tearDown(() {
    // Clean up temporary resources if needed
  });

  group('PricingCalculator Suite', () {
    test('calculates correct tax amount for standard rate', () {
      final tax = calculator.calculateTax(100.0, 0.08);

      // Value & Type Matchers:
      expect(tax, equals(8.0));
      expect(tax, isA<double>());
      expect(tax, isPositive);
    });

    test('throws ArgumentError when negative numbers are provided', () {
      expect(
        () => calculator.calculateTax(-50.0, 0.08),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fetches discounted price asynchronously', () async {
      final discounted = await calculator.fetchDiscountedPrice(100.0);
      expect(discounted, equals(90.0));
    });
  });
}
```

---

## 3. Testing Reactive Streams with `expectLater` & `emitsInOrder`

When testing asynchronous streams, use **`expectLater`** and stream matchers:

```dart
// test/unit/stream_test.dart
import 'package:test/test.dart';

Stream<int> generateCountStream() async* {
  yield 10;
  yield 20;
  yield 30;
}

void main() {
  test('stream emits expected sequence of numbers and closes', () async {
    final stream = generateCountStream();

    // Verify stream emissions in chronological sequence:
    await expectLater(
      stream,
      emitsInOrder([
        equals(10),
        equals(20),
        equals(30),
        emitsDone, // Stream closed cleanly!
      ]),
    );
  });
}
```

---

## 4. Modern Mocking with `package:mocktail`

Unlike legacy `mockito` (which required running slow `build_runner` code generation on every test file edit), **`mocktail`** utilizes Dart's sound type system and `noSuchMethod` to create typed mocks with **zero code generation**:

```dart
// test/unit/user_service_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

// 1. Production Interfaces:
abstract class UserDatabase {
  Future<Map<String, dynamic>?> getUser(String id);
  Future<void> saveUser(String id, Map<String, dynamic> data);
}

class UserService {
  final UserDatabase _db;
  UserService(this._db);

  Future<String> getUserName(String id) async {
    final user = await _db.getUser(id);
    if (user == null) throw Exception('User not found');
    return user['name'] as String;
  }
}

// 2. Mock Class definition (Zero build_runner needed!):
class MockUserDatabase extends Mock implements UserDatabase {}

void main() {
  late MockUserDatabase mockDb;
  late UserService userService;

  setUp(() {
    mockDb = MockUserDatabase();
    userService = UserService(mockDb);
  });

  group('UserService Tests with Mocktail', () {
    test('returns user name when record exists in database', () async {
      // 1. Stub the mock method behavior:
      when(() => mockDb.getUser('u_101')).thenAnswer(
        (_) async => {'id': 'u_101', 'name': 'Alice Chen'},
      );

      // 2. Execute service logic:
      final name = await userService.getUserName('u_101');

      // 3. Assertions:
      expect(name, equals('Alice Chen'));

      // 4. Verify mock was called with exact parameters:
      verify(() => mockDb.getUser('u_101')).called(1);
      verifyNever(() => mockDb.saveUser(any(), any()));
    });

    test('throws Exception when user is missing', () async {
      when(() => mockDb.getUser('u_missing')).thenAnswer((_) async => null);

      expect(
        () => userService.getUserName('u_missing'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
```

---

## 5. Code Coverage Analysis & HTML Reporting

Generate code coverage metrics from tests:

```bash

# 1. Run tests and collect coverage traces
dart test --coverage=coverage

# 2. Format coverage to LCOV format
dart pub global activate coverage
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --packages=.dart_tool/package_config.json \
  --report-on=lib

# 3. Generate HTML report (genhtml utility)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Troubleshooting & Best Practices

1. **`registerFallbackValue` in Mocktail**
   When using `any()` matchers with custom generic types, register a fallback value in `setUpAll(() => registerFallbackValue(MyCustomType()))` to allow Mocktail to satisfy Dart's sound non-null parameters.

2. **Always Use `await expectLater` for Async Matchers**
   If you omit `await` before `expectLater(stream, ...)`, the test function may complete and report success before the stream finished evaluating its assertions.
