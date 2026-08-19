# Module 12: Enterprise State Management with BLoC & Cubit

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** State Architecture, Event-Driven State Machines & BLoC Testing

---

## 1. The BLoC Architecture (Business Logic Component)

**BLoC** is an architectural pattern created by Google engineered around **Unidirectional Data Flow** and **State Machines**:

```text
BLoC Unidirectional Data Flow Cycle:
┌─────────────────────────────────────────────────────────────┐
│                       [UI Layer]                            │
│                            │                                │
│                            ▼ (Dispatches Event)             │
│                      [Event Stream]                         │
│                            │                                │
│                            ▼                                │
│                     [BLoC / Cubit]                          │
│         (Processes business logic & database/API)           │
│                            │                                │
│                            ▼ (Emits Immutable State)        │
│                      [State Stream]                         │
│                            │                                │
│                            ▼ (Rebuilds UI)                  │
│                       [UI Layer]                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. `Cubit` vs `Bloc`

The `flutter_bloc` ecosystem offers two approaches:

| Dimension | `Cubit<State>` | `Bloc<Event, State>` |
| :--- | :--- | :--- |
| **Complexity** | **Lightweight & Direct** | **Formal Event-Driven State Machine** |
| **Trigger Mechanism** | Direct function call (`cubit.increment()`) | Event dispatch (`bloc.add(IncrementEvent())`) |
| **Event Concurrency** | Standard async execution | **Custom Event Transformers** (`droppable`, `restartable`) |
| **Best For** | Simple forms, UI toggles, local settings | Complex workflows, authentication, payment pipelines, search |

---

## 3. Implementing an Enterprise Feature with `Bloc<Event, State>`

```yaml

# pubspec.yaml
dependencies:
  flutter_bloc: ^8.1.5
  equatable: ^2.0.5 # Value equality comparison for states and events
  bloc_concurrency: ^0.2.5 # Advanced event transformers (droppable, restartable)

dev_dependencies:
  bloc_test: ^9.1.7
```

### 1. Defining Events (`Equatable`)

```dart
// lib/features/auth/bloc/auth_event.dart
import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

final class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  const LoginRequested({required this.email, required this.password});
  @override
  List<Object?> get props => [email, password];
}

final class LogoutRequested extends AuthEvent {}
```

---

### 2. Defining States (`Equatable`)

```dart
// lib/features/auth/bloc/auth_state.dart
import 'package:equatable/equatable.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

final class AuthInitial extends AuthState {}
final class AuthLoading extends AuthState {}

final class AuthAuthenticated extends AuthState {
  final String userId;
  final String userEmail;
  const AuthAuthenticated({required this.userId, required this.userEmail});
  @override
  List<Object?> get props => [userId, userEmail];
}

final class AuthFailure extends AuthState {
  final String errorMessage;
  const AuthFailure(this.errorMessage);
  @override
  List<Object?> get props => [errorMessage];
}
```

---

### 3. The BLoC Implementation (`Bloc<AuthEvent, AuthState>`)

```dart
// lib/features/auth/bloc/auth_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    // 1. Handle Login Event with 'droppable' transformer (Ignores extra clicks while logging in!):
    on<LoginRequested>(
      _onLoginRequested,
      transformer: droppable(), // Prevents duplicate concurrent logins!
    );

    // 2. Handle Logout Event:
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      // Simulate backend authentication request:
      await Future.delayed(const Duration(milliseconds: 1000));

      if (event.password != 'Password123') {
        emit(const AuthFailure('Invalid credentials provided.'));
        return;
      }

      emit(AuthAuthenticated(
        userId: 'u_101',
        userEmail: event.email,
      ));
    } catch (e) {
      emit(AuthFailure('System error: $e'));
    }
  }

  void _onLogoutRequested(LogoutRequested event, Emitter<AuthState> emit) {
    emit(AuthInitial());
  }
}
```

---

## 4. Consuming BLoC in UI: `BlocConsumer` & `BlocBuilder`

```dart
// lib/features/auth/presentation/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enterprise BLoC Authentication')),
      body: BlocConsumer<AuthBloc, AuthState>(
        // 1. listener handles SIDE EFFECTS (Snackbars, Dialogs, Navigation):
        listener: (context, state) {
          if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage), backgroundColor: Colors.red),
            );
          } else if (state is AuthAuthenticated) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Welcome, ${state.userEmail}!')),
            );
          }
        },
        // 2. builder handles UI RENDERING:
        builder: (context, state) {
          if (state is AuthLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AuthAuthenticated) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Logged in as: ${state.userEmail}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<AuthBloc>().add(LogoutRequested()),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Dispatch event to BLoC:
                    context.read<AuthBloc>().add(
                          LoginRequested(
                            email: _emailController.text,
                            password: _passwordController.text,
                          ),
                        );
                  },
                  child: const Text('Sign In'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

---

## 5. Unit Testing BLoCs with `bloc_test`

```dart
// test/auth_bloc_test.dart
import 'package:test/test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:my_flutter_app/features/auth/bloc/auth_bloc.dart';
import 'package:my_flutter_app/features/auth/bloc/auth_event.dart';
import 'package:my_flutter_app/features/auth/bloc/auth_state.dart';

void main() {
  group('AuthBloc Unit Tests', () {
    late AuthBloc authBloc;

    setUp(() {
      authBloc = AuthBloc();
    });

    tearDown(() {
      authBloc.close();
    });

    test('initial state is AuthInitial', () {
      expect(authBloc.state, equals(AuthInitial()));
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when LoginRequested with valid credentials',
      build: () => authBloc,
      act: (bloc) => bloc.add(
        const LoginRequested(email: 'alice@acme.com', password: 'Password123'),
      ),
      expect: () => [
        AuthLoading(),
        const AuthAuthenticated(userId: 'u_101', userEmail: 'alice@acme.com'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthFailure] when LoginRequested with invalid password',
      build: () => authBloc,
      act: (bloc) => bloc.add(
        const LoginRequested(email: 'alice@acme.com', password: 'WrongPassword'),
      ),
      expect: () => [
        AuthLoading(),
        const AuthFailure('Invalid credentials provided.'),
      ],
    );
  });
}
```

---

## Troubleshooting & Best Practices

1. **Always Use `Equatable` for States and Events**
   BLoC compares the previous state with the newly emitted state. If you do not use `Equatable` or override `operator ==`, BLoC compares instances by reference equality, causing identical states to trigger redundant UI rebuilds.

2. **Never Emit in Async Callbacks After BLoC is Closed**
   If an asynchronous operation completes after the BLoC was closed, calling `emit()` throws a `StateError`. Always check `if (!isClosed) emit(...)`.
