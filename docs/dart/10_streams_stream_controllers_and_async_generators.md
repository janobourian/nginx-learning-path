# Module 10: Reactive Streams, `StreamController` & Asynchronous Generators (`async*`)

**Track:** Dart — Language & VM Architecture  
**Category:** Asynchronous Streams, Reactive Programming & Stream Generators

---

## 1. What Is a Dart `Stream<T>`?

While a `Future<T>` represents a single asynchronous computation that returns one value in the future, a **`Stream<T>`** is an asynchronous sequence of multiple data events arriving over time (e.g. WebSocket packets, file read chunks, UI clicks, timer ticks).

```
Stream Event Sequence:
---[Event 1]---[Event 2]---[Event 3]---[Done (Close)]---|
---[Event 1]---[Event 2]---[Error (Exception)]---------|
```

---

## 2. Single-Subscription vs Broadcast Streams

| Stream Type | Max Subscribers | Re-listening Allowed? | Typical Use Case |
| :--- | :--- | :--- | :--- |
| **Single-Subscription** (Default) | **Exactly 1** | No (Throws `StateError` if listened twice) | File I/O streaming, HTTP request body streams |
| **Broadcast Stream** | **Unlimited** | **Yes** (Multiple listeners can subscribe anytime) | Global event bus, WebSocket chat room, UI clicks |

```dart
import 'dart:async';

void main() {
  // 1. Single-Subscription Controller (Default):
  final singleController = StreamController<String>();

  // 2. Broadcast Controller (Multi-Listener):
  final broadcastController = StreamController<String>.broadcast();

  // Multiple listeners can subscribe to broadcast stream:
  broadcastController.stream.listen((msg) => print('[Listener 1]: $msg'));
  broadcastController.stream.listen((msg) => print('[Listener 2]: $msg'));

  broadcastController.add('Broadcasting system message');
  broadcastController.close();
}
```

---

## 3. Asynchronous Generators (`async*` & `yield`)

Dart provides native language support for creating streams using the **`async*`** keyword and the **`yield`** / **`yield*`** operators:

```dart
import 'dart:async';

// 1. Stream Generator emitting numbers with a timer delay:
Stream<int> countStream(int maxCount) async* {
  for (int i = 1; i <= maxCount; i++) {
    await Future.delayed(Duration(milliseconds: 200));
    yield i; // Emit next item to the stream!
  }
}

// 2. Delegating to another stream with yield*:
Stream<String> combinedStream() async* {
  yield 'START';
  // Delegate to another stream:
  yield* countStream(3).map((n) => 'Item #$n');
  yield 'END';
}

void main() async {
  // Consuming with 'await for':
  await for (final value in combinedStream()) {
    print('Received: $value');
  }
}
```

---

## 4. Consuming Streams: `await for` vs `.listen()`

### 1. The `await for` Loop (Sequential Consumption)

```dart
Future<double> sumStream(Stream<double> stream) async {
  double total = 0.0;
  // Automatically listens, pulls items, and completes when stream closes:
  await for (final val in stream) {
    total += val;
  }
  return total;
}
```

### 2. Manual Subscription Management (`.listen()`)

```dart
import 'dart:async';

class TelemetrySubscriber {
  StreamSubscription<int>? _subscription;

  void startListening(Stream<int> metricStream) {
    _subscription = metricStream.listen(
      (data) {
        print('Telemetry sample: $data');
      },
      onError: (err) {
        print('Telemetry stream error: $err');
      },
      onDone: () {
        print('Telemetry stream completed.');
      },
      cancelOnError: false, // Keep stream open on non-fatal errors
    );
  }

  void stop() {
    // Crucial: Always cancel subscriptions to prevent memory leaks!
    _subscription?.cancel();
    _subscription = null;
  }
}
```

---

## 5. Stream Transformations & `StreamTransformer`

Streams provide powerful transformation operators:

```dart
import 'dart:async';

void main() async {
  final rawNumbers = Stream.fromIterable([1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

  final processedStream = rawNumbers
      .where((n) => n.isEven)         // Filter even numbers: [2, 2, 4, 6, 8, 10]
      .distinct()                     // Drop consecutive duplicates: [2, 4, 6, 8, 10]
      .map((n) => n * 10)             // Multiply: [20, 40, 60, 80, 100]
      .take(3);                       // Take first 3: [20, 40, 60]

  await for (final num in processedStream) {
    print('Processed: $num');
  }
}
```

### Custom `StreamTransformer`:

```dart
// Custom Transformer: Decodes UTF8 bytes and splits into text lines
final lineSplitterTransformer = StreamTransformer<List<int>, String>.fromHandlers(
  handleData: (bytes, sink) {
    // Process and push decoded string lines to sink
  },
);
```

---

## Troubleshooting & Best Practices

1. **Always Close `StreamController`**
   If you instantiate a `StreamController`, always invoke `controller.close()` when finished to notify active subscribers that the stream has completed.

2. **`Bad state: Stream has already been listened to`**
   This error occurs when attempting to call `.listen()` twice on a single-subscription stream. Convert it to a broadcast stream using `stream.asBroadcastStream()` or use `StreamController.broadcast()`.
