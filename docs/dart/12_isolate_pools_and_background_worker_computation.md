# Module 12: Enterprise Isolate Pools & High-Throughput Worker Systems

**Track:** Dart — Language & VM Architecture  
**Category:** Concurrency Engineering, Isolate Pools & Multicore Task Scheduling

---

## 1. Why Isolate Pools Are Essential for Enterprise Systems

While `Isolate.run()` is convenient for occasional one-off jobs, spawning an isolate incurs an allocation overhead of ~15–30ms and several megabytes of heap memory.

In high-throughput enterprise backends (e.g. processing 10,000 image thumbnails, cryptographic verification, or PDF rendering per second):
- Spawning and tearing down thousands of isolates per second exhausts OS thread handles and saturates CPU time with VM bootstrap overhead.
- An **Isolate Pool** pre-warms a fixed cluster of persistent worker isolates matching the host CPU core count (`Platform.numberOfProcessors`), distributing tasks via load-balancing queues with **sub-millisecond dispatch latency**.

```
Isolate Worker Pool Architecture:
                    ┌────────────────────────────┐
                    │      Task Queue Stream     │
                    └─────────────┬──────────────┘
                                  │ Load Balancer (Round-Robin / Least-Loaded)
            ┌─────────────────────┼─────────────────────┐
            ▼                     ▼                     ▼
┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
│ Worker Isolate #1 │ │ Worker Isolate #2 │ │ Worker Isolate #3 │ (Pre-warmed Heap)
└───────────────────┘ └───────────────────┘ └───────────────────┘
```

---

## 2. Complete Enterprise Isolate Worker Pool Implementation

```dart
// src/concurrency/isolate_pool.dart
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// 1. Task Definition
class PoolTask<TInput, TOutput> {
  final String taskId;
  final TInput input;
  final Completer<TOutput> completer;
  final TOutput Function(TInput) computation;

  PoolTask({
    required this.taskId,
    required this.input,
    required this.completer,
    required this.computation,
  });
}

// 2. Internal Worker Node Representation
class _WorkerNode {
  final int workerId;
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;
  bool isBusy = false;
  int completedTasksCount = 0;

  _WorkerNode({
    required this.workerId,
    required this.isolate,
    required this.sendPort,
    required this.receivePort,
  });
}

// 3. The Master IsolatePool
class EnterpriseIsolatePool {
  final int poolSize;
  final List<_WorkerNode> _workers = [];
  final List<PoolTask<dynamic, dynamic>> _taskQueue = [];
  final Map<String, Completer<dynamic>> _pendingTaskCompleters = {};
  bool _isDisposed = false;

  EnterpriseIsolatePool({int? size})
      : poolSize = size ?? Platform.numberOfProcessors;

  // Bootstraps and pre-warms the worker pool:
  Future<void> initialize() async {
    print('Initializing Enterprise Isolate Pool with $poolSize workers...');

    for (int i = 0; i < poolSize; i++) {
      final worker = await _spawnWorker(i);
      _workers.add(worker);
    }

    print('Isolate Pool pre-warmed and ready to process computations.');
  }

  Future<_WorkerNode> _spawnWorker(int id) async {
    final initReceivePort = ReceivePort();

    final isolate = await Isolate.spawn(
      _workerEntryPoint,
      initReceivePort.sendPort,
      debugName: 'Worker_$id',
    );

    // Wait for worker's SendPort:
    final workerSendPort = await initReceivePort.first as SendPort;
    final workerResponsePort = ReceivePort();

    // Re-bind worker message handler:
    workerResponsePort.listen((dynamic message) {
      if (message is _WorkerExecutionResult) {
        _handleTaskCompletion(id, message);
      }
    });

    // Send task communication port to worker:
    workerSendPort.send(workerResponsePort.sendPort);

    return _WorkerNode(
      workerId: id,
      isolate: isolate,
      sendPort: workerSendPort,
      receivePort: workerResponsePort,
    );
  }

  // Submit a computation job to the pool:
  Future<TOutput> submit<TInput, TOutput>(
    TInput input,
    TOutput Function(TInput) computation,
  ) {
    if (_isDisposed) throw StateError('IsolatePool is disposed.');

    final taskId = 'task_${DateTime.now().microsecondsSinceEpoch}_${_taskQueue.length}';
    final completer = Completer<TOutput>();

    final task = PoolTask<TInput, TOutput>(
      taskId: taskId,
      input: input,
      completer: completer,
      computation: computation,
    );

    _taskQueue.add(task);
    _pendingTaskCompleters[taskId] = completer;

    _dispatchNext();

    return completer.future;
  }

  void _dispatchNext() {
    if (_taskQueue.isEmpty) return;

    // Find first available idle worker:
    final availableWorker = _workers.where((w) => !w.isBusy).firstOrNull;
    if (availableWorker == null) return; // All workers busy; remains queued

    final task = _taskQueue.removeAt(0);
    availableWorker.isBusy = true;

    // Dispatch task payload to worker isolate:
    availableWorker.sendPort.send(_WorkerExecutionRequest(
      taskId: task.taskId,
      input: task.input,
      computation: task.computation,
    ));
  }

  void _handleTaskCompletion(int workerId, _WorkerExecutionResult result) {
    final worker = _workers.firstWhere((w) => w.workerId === workerId, orElse: () => _workers[workerId]);
    worker.isBusy = false;
    worker.completedTasksCount++;

    final completer = _pendingTaskCompleters.remove(result.taskId);
    if (completer != null) {
      if (result.error != null) {
        completer.completeError(result.error!);
      } else {
        completer.complete(result.output);
      }
    }

    // Check if more tasks are queued:
    _dispatchNext();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    for (final worker in _workers) {
      worker.sendPort.send('SHUTDOWN');
      worker.receivePort.close();
      worker.isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
  }
}

// 4. Worker Serialization Envelopes
class _WorkerExecutionRequest {
  final String taskId;
  final dynamic input;
  final dynamic Function(dynamic) computation;
  _WorkerExecutionRequest({
    required this.taskId,
    required this.input,
    required this.computation,
  });
}

class _WorkerExecutionResult {
  final String taskId;
  final dynamic output;
  final Object? error;
  _WorkerExecutionResult({required this.taskId, this.output, this.error});
}

// 5. Worker Entry Function
void _workerEntryPoint(SendPort initSendPort) {
  final initPort = ReceivePort();
  initSendPort.send(initPort.sendPort);

  initPort.listen((dynamic message) {
    if (message is SendPort) {
      final taskPort = ReceivePort();
      message.send(taskPort.sendPort);

      taskPort.listen((dynamic taskMsg) {
        if (taskMsg is _WorkerExecutionRequest) {
          try {
            final output = taskMsg.computation(taskMsg.input);
            message.send(_WorkerExecutionResult(taskId: taskMsg.taskId, output: output));
          } catch (err) {
            message.send(_WorkerExecutionResult(taskId: taskMsg.taskId, error: err));
          }
        }
      });
    }
  });
}
```

---

## 3. High-Throughput Batch Processing Demo

```dart
void main() async {
  final pool = EnterpriseIsolatePool();
  await pool.initialize();

  final stopwatch = Stopwatch()..start();
  print('Submitting 1,000 CPU hashing tasks across isolate pool...');

  // Dispatches 1,000 cryptographic/calculation jobs across all CPU cores:
  final futures = List.generate(1000, (index) {
    return pool.submit<int, int>(index, (input) {
      // Simulate heavy calculation:
      int hash = 0;
      for (int i = 0; i < 100000; i++) {
        hash = (hash + input * 31) ^ i;
      }
      return hash;
    });
  });

  final results = await Future.wait(futures);
  stopwatch.stop();

  print('Processed ${results.length} tasks in ${stopwatch.elapsedMilliseconds}ms.');
  await pool.dispose();
}
```

---

## Troubleshooting & Best Practices

1. **Optimal Pool Sizing**
   Set `poolSize = Platform.numberOfProcessors`. Allocating more worker isolates than physical CPU threads will cause OS context-switching overhead without increasing throughput.

2. **Top-Level or Static Functions for Computations**
   Functions passed across isolate boundaries **must be top-level or static functions**; they cannot capture closures from local component state.
