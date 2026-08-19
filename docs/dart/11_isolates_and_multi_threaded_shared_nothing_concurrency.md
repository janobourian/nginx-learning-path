# Module 11: Isolates & Multi-Threaded Shared-Nothing Concurrency

**Track:** Dart — Language & VM Architecture
**Category:** Concurrency, Actor Model & Isolate Memory Isolation

---

## 1. What Is a Dart Isolate?

In traditional multithreaded runtimes (Java, C++, Rust), threads share the same heap memory space, requiring mutexes, semaphores, and locks to prevent race conditions and memory corruption.

In Dart, concurrency is designed around the **Actor Model** using **Isolates**:

1. **Shared-Nothing Memory**: Every isolate has its **own private heap memory space** and its own independent **Event Loop**.
2. **Zero Lock Contention**: Because memory is not shared, there are **no race conditions, no deadlocks, and no mutex locks** in Dart application code!
3. **Message-Passing Communication**: Isolates communicate exclusively by passing messages through **`SendPort`** and **`ReceivePort`** channels.

```text
Isolate Architecture (Shared-Nothing Memory Model):
┌──────────────────────────────┐        ┌──────────────────────────────┐
│       Main UI Isolate        │        │      Worker Isolate A        │
│  [Private Heap Memory]       │        │  [Private Heap Memory]       │
│  [Single Event Loop]         │        │  [Single Event Loop]         │
│  SendPort A ─────────────────┼───────►│ ReceivePort                  │
│  ReceivePort ◄───────────────┼────────┼── SendPort Main              │
└──────────────────────────────┘        └──────────────────────────────┘
```

---

## 2. One-Off Background Work with `Isolate.run()` (Dart 2.19+)

For short-lived, CPU-intensive tasks (e.g. parsing 50MB JSON files, compressing images, hashing passwords), **`Isolate.run()`** spawns an isolate, runs the computation, transfers the result back, and automatically terminates the isolate:

```dart
import 'dart:convert';
import 'dart:isolate';

// Heavy CPU-intensive parsing function:
List<Map<String, dynamic>> parseHeavyJson(String rawJsonString) {
  final dynamic parsed = jsonDecode(rawJsonString);
  return (parsed as List<dynamic>).cast<Map<String, dynamic>>();
}

Future<void> main() async {
  final rawBigData = '[{"id": 1, "val": 100}, {"id": 2, "val": 200}]';

  print('1. Offloading heavy JSON parse to background isolate...');

  // Isolate.run spawns a worker thread, executes, and returns the result without blocking main UI!
  final List<Map<String, dynamic>> records = await Isolate.run(
    () => parseHeavyJson(rawBigData),
  );

  print('2. Received ${records.length} parsed records from worker isolate!');
}
```

---

## 3. Long-Lived Worker Isolates & The Two-Way Handshake

For continuous background tasks (e.g. audio processing, continuous WebSocket data decoding, database sync), maintain a persistent worker isolate using **`Isolate.spawn()`** and a two-way **Handshake Protocol**:

```dart
import 'dart:async';
import 'dart:isolate';

// 1. Worker Configuration Message
class WorkerMessage {
  final String taskId;
  final List<int> payload;
  WorkerMessage(this.taskId, this.payload);
}

class WorkerResponse {
  final String taskId;
  final int checksum;
  WorkerResponse(this.taskId, this.checksum);
}

// 2. The Worker Entry Point (Runs in separate isolate!)
void workerEntryPoint(SendPort mainSendPort) {
  // Create a ReceivePort for this worker isolate:
  final workerReceivePort = ReceivePort();

  // Send worker's SendPort back to main isolate (Handshake step 1):
  mainSendPort.send(workerReceivePort.sendPort);

  // Listen for incoming task messages from main isolate:
  workerReceivePort.listen((dynamic message) {
    if (message is WorkerMessage) {
      // Execute CPU calculation:
      final checksum = message.payload.fold<int>(0, (a, b) => a ^ b);

      // Send result back to main isolate:
      mainSendPort.send(WorkerResponse(message.taskId, checksum));
    } else if (message == 'TERMINATE') {
      workerReceivePort.close();
      Isolate.current.kill();
    }
  });
}

// 3. Main Controller Managing the Worker
class BackgroundWorkerController {
  late Isolate _isolate;
  late SendPort _workerSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  final Completer<void> _readyCompleter = Completer<void>();

  Future<void> init() async {
    // Spawn background isolate:
    _isolate = await Isolate.spawn(workerEntryPoint, _mainReceivePort.sendPort);

    // Listen for incoming messages from worker:
    _mainReceivePort.listen((dynamic message) {
      if (message is SendPort) {
        // Complete the handshake:
        _workerSendPort = message;
        _readyCompleter.complete();
      } else if (message is WorkerResponse) {
        print('[Main]: Task ${message.taskId} completed! Checksum: ${message.checksum}');
      }
    });

    await _readyCompleter.future;
    print('[Main]: Two-way isolate communication established!');
  }

  void dispatchTask(String taskId, List<int> data) {
    _workerSendPort.send(WorkerMessage(taskId, data));
  }

  void dispose() {
    _workerSendPort.send('TERMINATE');
    _mainReceivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}
```

---

## 4. Zero-Copy Buffer Transfer with `TransferableTypedData`

When passing large byte buffers (e.g. 500MB video/audio buffers) between isolates, copying the memory bytes causes high memory overhead.

Use **`TransferableTypedData`** to transfer ownership of the underlying native byte buffer across isolate boundaries **in O(1) time without copying memory**:

```dart
import 'dart:isolate';
import 'dart:typed_data';

void processBufferIsolate(SendPort replyPort) {
  final port = ReceivePort();
  replyPort.send(port.sendPort);

  port.listen((dynamic message) {
    if (message is TransferableTypedData) {
      // Materialize the transferred byte buffer (Zero-copy transfer!):
      final Uint8List bytes = message.materialize().asUint8List();
      print('Worker received ${bytes.lengthInBytes} bytes with zero-copy transfer.');
      replyPort.send('DONE');
    }
  });
}
```

---

## Troubleshooting & Best Practices

1. **What Objects Can Be Sent Across Isolates?**
   Primitive types (`int`, `String`, `bool`, `double`), standard collections (`List`, `Map`, `Set`), `SendPort`, `TransferableTypedData`, and user-defined instances containing serializable fields can be sent across isolates.
   *Note: Functions with lexical closures over local state or platform handles cannot be sent.*

2. **Always Kill Unused Isolates**
   Leaving background worker isolates alive prevents the Dart VM process from exiting. Always call `isolate.kill()` or send a shutdown signal when terminating worker pools.
