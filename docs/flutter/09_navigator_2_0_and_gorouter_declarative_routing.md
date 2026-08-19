# Module 09: Declarative Routing with `go_router` & Deep Linking

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** Declarative Navigation, Router Architecture & Deep Linking

---

## 1. The Evolution of Flutter Routing: Navigator 1.0 to `go_router`

In legacy Flutter (Navigator 1.0), navigation was imperative:

```dart
Navigator.push(context, MaterialPageRoute(builder: (c) => DetailScreen()));
```

While simple for basic mobile apps, Navigator 1.0 failed on Web and Desktop:

- The browser URL bar did not synchronize with the navigation stack.
- The browser "Back" button broke navigation stacks.
- Deep linking (e.g. clicking `myapp://profile/42` in an email) was brittle.

**`go_router`** is the official, declarative routing package maintained by the Flutter team built on top of Flutter's Navigator 2.0 Router API.

```text
┌─────────────────────────────────────────────────────────────┐
│                 Why go_router Is the Standard               │
├─────────────────────────────────────────────────────────────┤
│ 1. **URL & Deep-Link Synchronization**: Native URL bar sync │
│    across Web, iOS, Android, and Desktop.                   │
├─────────────────────────────────────────────────────────────┤
│ 2. **Declarative Route Tree**: Nested child routes with     │
│    path parameter parsing (`/projects/:projectId/edit`).    │
├─────────────────────────────────────────────────────────────┤
│ 3. **`StatefulShellRoute`**: Persistent Bottom Navigation   │
│    bars that preserve independent tab scroll state!         │
├─────────────────────────────────────────────────────────────┤
│ 4. **Centralized Redirect Guards**: Global authentication   │
│    redirects evaluated before route transitions.            │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Setting Up `go_router`

```yaml

# pubspec.yaml
dependencies:
  go_router: ^14.0.0
```

### Basic `GoRouter` Configuration

```dart
// lib/core/routing/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: [
    // 1. Root Home Route
    GoRoute(
      path: '/',
      name: 'home',
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
      routes: [
        // 2. Parameterized Child Route (/details/:id?tab=analytics)
        GoRoute(
          path: 'details/:id',
          name: 'details',
          builder: (BuildContext context, GoRouterState state) {
            final id = state.pathParameters['id'] ?? '';
            final activeTab = state.uri.queryParameters['tab'] ?? 'overview';

            return DetailScreen(id: id, initialTab: activeTab);
          },
        ),
      ],
    ),
  ],
);
```

### Integrating with `MaterialApp.router`

```dart
// lib/main.dart
void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter, // ◄── Mount declarative router config!
      title: 'Enterprise Flutter',
      theme: ThemeData.dark(),
    );
  }
}
```

---

## 3. Persistent Tabs with `StatefulShellRoute`

In mobile applications with a **BottomNavigationBar**, users expect each tab (e.g. Home, Search, Settings) to maintain its own independent navigation stack and scroll position when switching tabs.

Use **`StatefulShellRoute.indexedStack`**:

```dart
// lib/core/routing/shell_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GoRouter shellAppRouter = GoRouter(
  initialLocation: '/feed',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        // Return the persistent shell layout wrapping the active tab branch:
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (int index) {
              // Switch tab branch and preserve scroll state:
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.feed), label: 'Feed'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
      branches: [
        // Branch 1: Feed Tab
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/feed', builder: (c, s) => const FeedScreen()),
          ],
        ),
        // Branch 2: Search Tab
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/search', builder: (c, s) => const SearchScreen()),
          ],
        ),
        // Branch 3: Profile Tab
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          ],
        ),
      ],
    ),
  ],
);
```

---

## 4. Centralized Authentication Redirects

```dart
// lib/core/routing/auth_redirect_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AuthService extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  void login() {
    _isAuthenticated = true;
    notifyListeners();
  }

  void logout() {
    _isAuthenticated = false;
    notifyListeners();
  }
}

final authService = AuthService();

final GoRouter protectedRouter = GoRouter(
  initialLocation: '/dashboard',
  refreshListenable: authService, // Re-evaluates redirects when auth changes!
  redirect: (BuildContext context, GoRouterState state) {
    final loggedIn = authService.isAuthenticated;
    final isGoingToLogin = state.matchedLocation == '/login';

    // 1. If not logged in and trying to access protected area -> Redirect to /login
    if (!loggedIn && !isGoingToLogin) {
      return '/login';
    }

    // 2. If already logged in and visiting /login -> Redirect to /dashboard
    if (loggedIn && isGoingToLogin) {
      return '/dashboard';
    }

    // No redirect needed:
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
  ],
);
```

---

## 5. Programmatic Navigation with `context.go()` vs `context.push()`

| Navigation Command | Behavior | When to Use |
| :--- | :--- | :--- |
| **`context.go('/path')`** | Replaces the current navigation location with the target URL path. | Tab switches, top-level route changes |
| **`context.push('/path')`** | Pushes a new page onto the current page stack with a Back button. | Modal details, nested forms |
| **`context.pop()`** | Pops the top-most route off the navigation stack. | Dismissing dialogs, back button |

---

## Troubleshooting & Best Practices

1. **`context.go` vs `context.push` on Web**
   Prefer `context.go('/items/123')` for declarative routes. Using `context.push()` stacks screens imperatively without synchronizing the browser URL path hierarchy cleanly.

2. **Always Use `refreshListenable` with State Notifiers**
   When attaching authentication redirects to `GoRouter`, pass your `AuthService` (implementing `Listenable` / `ChangeNotifier`) to `refreshListenable`. Whenever the user logs in or out, `GoRouter` automatically re-evaluates all redirect rules without manual navigation code.
