# Module 11: Modern State Management with Riverpod 2.0 & Code Generators

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** State Architecture, Riverpod Generators & Asynchronous Values

---

## 1. Why Riverpod Was Created (Provider 2.0)

**Riverpod** (an anagram of *Provider*) was created by Remi Rousselet (the original author of Provider) to eliminate the fundamental architectural constraints of `BuildContext`-based state management:

| Limitation in Provider | How Riverpod Solves It |
| :--- | :--- |
| **`ProviderNotFoundException`** at runtime if provider is placed in the wrong widget tree branch. | **Compile-Time Safe**: Providers are declared globally as top-level constants. Runtime `ProviderNotFoundException` is **impossible**! |
| **Tightly coupled to `BuildContext`**. Cannot read state inside business services or repositories. | **Zero `BuildContext` Requirement**: State can be read and listened to anywhere via `Ref`. |
| **Cumbersome Async State**: Manual loading booleans, error strings, and try-catch boilerplate. | **Native `AsyncValue<T>`**: Declarative pattern matching across `.when(data, loading, error)`. |
| **Testing requires mounting full Flutter widget trees**. | **Unit Testing Without Widgets**: Override any provider in pure Dart unit tests with zero mock boilerplate! |

---

## 2. Setting Up Riverpod with Code Generation

Modern Riverpod utilizes **`riverpod_annotation`** and **`build_runner`** for clean, boilerplate-free type generation:

```yaml

# pubspec.yaml
dependencies:
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

dev_dependencies:
  build_runner: ^2.4.9
  riverpod_generator: ^2.4.0
```

Wrap your root application in **`ProviderScope`**:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    // ProviderScope holds all in-memory state for the entire application:
    const ProviderScope(
      child: MyAppRoot(),
    ),
  );
}
```

---

## 3. Defining Providers with `@riverpod` Annotations

Run code generation watcher:

```bash
dart run build_runner watch -d
```

### 1. Functional Provider (Read-Only Computed Value)

```dart
// lib/features/settings/providers/api_config_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_config_provider.g.dart';

@riverpod
String apiBaseUrl(ApiBaseUrlRef ref) {
  return 'https://api.enterprise.acme.com/v1';
}
```

---

### 2. Synchronous Notifier Provider (`@riverpod class`)

```dart
// lib/features/counter/providers/counter_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'counter_provider.g.dart';

@riverpod
class Counter extends _$Counter {
  @override
  int build() {
    return 0; // Initial state value
  }

  void increment() {
    state = state + 1; // Immutable state update!
  }

  void decrement() {
    state = state - 1;
  }

  void reset() {
    state = 0;
  }
}
```

---

### 3. Asynchronous Notifier (`AsyncNotifier` with Auto-Caching & Invalidation)

```dart
// lib/features/projects/providers/projects_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'projects_provider.g.dart';

class ProjectItem {
  final String id;
  final String title;
  const ProjectItem({required this.id, required this.title});
}

@riverpod
class ProjectsNotifier extends _$ProjectsNotifier {
  @override
  Future<List<ProjectItem>> build() async {
    // 1. Fetch initial data from network/database:
    return _fetchProjectsFromBackend();
  }

  Future<List<ProjectItem>> _fetchProjectsFromBackend() async {
    await Future.delayed(const Duration(milliseconds: 800)); // Network delay
    return [
      const ProjectItem(id: 'p_1', title: 'Impeller Engine Migration'),
      const ProjectItem(id: 'p_2', title: 'Riverpod 2.0 Integration'),
    ];
  }

  Future<void> addProject(String title) async {
    // Set state to loading:
    state = const AsyncValue.loading();

    // Execute mutation and update local state:
    state = await AsyncValue.guard(() async {
      await Future.delayed(const Duration(milliseconds: 300));
      final currentList = state.value ?? [];
      final newItem = ProjectItem(id: 'p_${DateTime.now().millisecondsSinceEpoch}', title: title);
      return [...currentList, newItem];
    });
  }
}
```

---

## 4. Consuming Riverpod State in UI: `ConsumerWidget` & `WidgetRef`

Instead of `StatelessWidget`, inherit from **`ConsumerWidget`** which receives a **`WidgetRef ref`**:

```dart
// lib/features/projects/presentation/projects_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/projects_provider.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. ref.watch(): Subscribes reactively to the AsyncValue state:
    final AsyncValue<List<ProjectItem>> projectsState = ref.watch(projectsNotifierProvider);

    // 2. ref.listen(): Listens for side effects (e.g. snackbars or dialogs):
    ref.listen(projectsNotifierProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${next.error}')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enterprise Projects (Riverpod)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Invalidate provider to force background re-fetch!
              ref.invalidate(projectsNotifierProvider);
            },
          ),
        ],
      ),
      // 3. Declarative Async Pattern Matching:
      body: projectsState.when(
        data: (projects) => ListView.builder(
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.indigoAccent),
              title: Text(project.title),
              subtitle: Text('ID: ${project.id}'),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('Failed to load projects: $err', style: const TextStyle(color: Colors.red)),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 4. ref.read(): Access notifier methods without subscribing to rebuilds:
          ref.read(projectsNotifierProvider.notifier).addProject('New Telemetry Node');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

---

## 5. Unit Testing Riverpod State Without Flutter UI

Because Riverpod providers do not depend on `BuildContext`, you can test them directly in pure Dart unit tests:

```dart
// test/projects_provider_test.dart
import 'package:test/test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_flutter_app/features/projects/providers/projects_provider.dart';

void main() {
  test('ProjectsNotifier initializes with default projects and adds new items', () async {
    // 1. Create a lightweight in-memory ProviderContainer:
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 2. Read initial async state:
    final initialProjects = await container.read(projectsNotifierProvider.future);
    expect(initialProjects.length, equals(2));

    // 3. Trigger mutation:
    await container.read(projectsNotifierProvider.notifier).addProject('Test Project');

    // 4. Assert updated state:
    final updatedProjects = container.read(projectsNotifierProvider).value!;
    expect(updatedProjects.length, equals(3));
    expect(updatedProjects.last.title, equals('Test Project'));
  });
}
```

---

## Troubleshooting & Best Practices

1. **`ref.watch()` vs `ref.read()`**

   - Use **`ref.watch()`** inside the `build()` method to subscribe to state changes.
   - Use **`ref.read()`** inside button click callbacks (`onPressed`) or async methods to invoke actions. Never call `ref.read` inside `build()`.

2. **AutoDispose by Default**
   Riverpod 2.0 generator providers are `@riverpod` (auto-disposed by default when no active UI widgets are listening), preventing memory leaks. If you want a provider to persist indefinitely in memory, annotate with `@Riverpod(keepAlive: true)`.
