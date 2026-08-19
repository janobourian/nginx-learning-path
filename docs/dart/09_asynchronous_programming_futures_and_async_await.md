# Module 09: Asynchronous Programming — `Future`, `async`/`await` & Event Loop

**Track:** Dart — Language & VM Architecture
**Category:** Asynchronous Runtimes, Event Loops & Microtask Queues

---

## 1. The Dart Event Loop Architecture

Like JavaScript and Node.js, a Dart isolate runs on a **Single-Threaded Event Loop**. Concurrency in a single isolate is achieved via asynchronous non-blocking event scheduling.

The Dart Event Loop manages **two distinct queues**:

```text
┌─────────────────────────────────────────────────────────────┐
│                    The Dart Event Loop                      │
│                                                             │
│  [1. Microtask Queue] (Highest Priority)                    │
│      - Handled BEFORE any item from the Event Queue!        │
│      - Scheduled via `scheduleMicrotask()` or Future.micro()│
│                                                             │
│  [2. Event Queue] (Standard I/O & Timers)                   │
│      - Network I/O, File System reads, Socket events        │
│      - Timer events (`Future.delayed`, `Timer.periodic`)    │
│      - Isolate port messages                                │
└─────────────────────────────────────────────────────────────┘
```

### Execution Rule

The Event Loop **drains the entire Microtask Queue to empty** before pulling the next event from the Event Queue.

```dart
import 'dart:async';

void main() {
  print('1. Sync Start');

  // Event Queue:
  Timer.run(() => print('4. Event Queue Timer'));

  // Microtask Queue:
  scheduleMicrotask(() => print('3. Microtask Queue'));

  // Future (Schedules on Event Queue by default):
  Future(() => print('5. Future on Event Queue'));

  print('2. Sync End');
}
// Execution Output:
// 1. Sync Start
// 2. Sync End
// 3. Microtask Queue
// 4. Event Queue Timer
// 5. Future on Event Queue
```

---

## 2. The Anatomy of a `Future<T>`

A **`Future<T>`** represents a computation that will produce a result of type `T` (or an error) at some point in the future.

```text
Future State Lifecycle:
[Uncompleted (Pending)]
       │
       ├─► [Completed with Value (T)]  ──► Trigger await / .then()
       └─► [Completed with Error (Err)] ──► Trigger catch / .catchError()
```

---

## 3. `async` / `await` & Exception Handling

The `async` keyword marks a function as asynchronous (always returns a `Future<T>`), and `await` pauses execution until the awaited Future completes:

```dart
import 'dart:io';

class NetworkException implements Exception {
  final String message;
  final int statusCode;
  NetworkException(this.message, this.statusCode);
  @override
  String toString() => 'NetworkException ($statusCode): $message';
}

Future<String> fetchUserPayload(String userId) async {
  // Simulate network request:
  await Future.delayed(Duration(milliseconds: 500));

  if (userId == 'invalid') {
    throw NetworkException('User not found on remote cluster', 404);
  }

  return '{"id": "$userId", "name": "Alice Chen", "status": "active"}';
}

Future<void> executeUserWorkflow() async {
  try {
    print('Initiating user payload fetch...');
    final json = await fetchUserPayload('u_101');
    print('Received payload: $json');
  } on NetworkException catch (e) {
    // Specific typed exception catch:
    stderr.writeln('Network Error occurred: $e');
  } catch (e, stackTrace) {
    // General fallback catch:
    stderr.writeln('Unexpected error: $e\n$stackTrace');
  } finally {
    print('Workflow cleanup completed.');
  }
}
```

---

## 4. Future Combinators: `wait`, `any` & `delayed`

### 1. `Future.wait()` (Parallel Execution)

Executes multiple asynchronous operations concurrently and waits for all to finish (equivalent to `Promise.all`):

```dart
Future<void> loadDashboardMetrics() async {
  final stopwatch = Stopwatch()..start();

  // Run all 3 queries in parallel:
  final results = await Future.wait([
    fetchUsersCount(),       // Takes 300ms
    fetchRevenueTotal(),     // Takes 400ms
    fetchServerHealthRate(), // Takes 200ms
  ]);

  final users = results[0] as int;
  final revenue = results[1] as double;
  final health = results[2] as String;

  print('Dashboard loaded in ${stopwatch.elapsedMilliseconds}ms: Users=$users, Rev=\$$revenue, Health=$health');
}
```

### 2. `Future.any()` (First to Complete)

Returns the value of whichever Future completes first (equivalent to `Promise.race`):

```dart
Future<String> fetchFastestMirror() async {
  return await Future.any([
    fetchFromMirror('https://us-east.api.com'),
    fetchFromMirror('https://eu-west.api.com'),
    fetchFromMirror('https://ap-south.api.com'),
  ]);
}
```

---

## 5. Bridging Callback APIs with `Completer<T>`

When interfacing with legacy event-driven or callback-based libraries, use a **`Completer<T>`** to manually create and control a `Future`:

```dart
import 'dart:async';

class LegacyCallbackService {
  void registerListener(void Function(String result) onSuccess, void Function(Object err) onError) {
    // Legacy async callback execution
  }
}

// Convert Callback API to modern Future with Completer:
Future<String> convertCallbackToFuture(LegacyCallbackService service) {
  final completer = Completer<String>();

  service.registerListener(
    (result) {
      if (!completer.isCompleted) {
        completer.complete(result); // Complete Future with Value!
      }
    },
    (error) {
      if (!completer.isCompleted) {
        completer.completeError(error); // Complete Future with Error!
      }
    },
  );

  return completer.future;
}
```

---

## Troubleshooting & Best Practices

1. **Beware of Unhandled Errors in `Future.wait`**
   By default, `Future.wait` terminates on the first error. If you want all futures to finish regardless of errors, set `eagerError: false`.

2. **Never Leave Futures Unawaited**
   Always `await` futures or explicitly pass them to `unawaited(myFuture)` from `dart:async` to document intentional fire-and-forget background execution.
