# Module 15: Enterprise Networking — `Dio`, JSON Serialization & Offline Caching

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** Networking Architecture, Interceptors & Code-Generated Serialization

---

## 1. Why Dio Is the Enterprise Standard for Flutter

While the standard `http` package handles basic GET/POST requests, **`Dio`** provides enterprise-grade networking features:

- **Interceptor Chains** (Auth token injection, global logging, automated 401 token refresh).
- **Request Cancellation** via `CancelToken` (e.g. canceling in-flight search requests on screen exit).
- **File Upload & Download Progress** callbacks.
- **Offline HTTP Response Caching** backed by SQLite / Hive stores.

```text
Dio Request Pipeline:
[Outgoing Request] ──► [AuthInterceptor] ──► [CacheInterceptor] ──► [LoggingInterceptor] ──► Network
                                                                                               │
[Incoming Response] ◄── [ErrorInterceptor] ◄── [CacheWriter] ◄── [LoggingInterceptor] ◄──────┘
```

---

## 2. Setting Up Dio with Code-Generated JSON Serialization

```yaml

# pubspec.yaml
dependencies:
  dio: ^5.4.3+1
  dio_cache_interceptor: ^3.5.0
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.4.9
  json_serializable: ^6.8.0
```

---

## 3. Type-Safe Data Models with `json_serializable`

```dart
// lib/features/users/data/models/user_model.dart
import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable(explicitToJson: true)
class UserModel {
  final String id;

  @JsonKey(name: 'full_name')
  final String fullName;

  final String email;

  @JsonKey(name: 'is_active', defaultValue: true)
  final bool isActive;

  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isActive,
    required this.createdAt,
  });

  // Code-generated deserialization:
  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);

  // Code-generated serialization:
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}
```

Run code generator:

```bash
dart run build_runner build -d
```

---

## 4. Enterprise Dio Client with Interceptors & Token Refresh

```dart
// lib/core/network/api_client.dart
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

class ApiClient {
  late final Dio _dio;

  Dio get dio => _dio;

  ApiClient({required String baseUrl, required String Function() getAuthToken}) {
    // 1. Base Options:
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );

    _dio = Dio(options);

    // 2. Setup Offline Cache Options:
    final cacheOptions = CacheOptions(
      store: MemCacheStore(), // In-memory or Hive/SQLite store
      policy: CachePolicy.request,
      maxStale: const Duration(days: 7),
    );

    // 3. Register Interceptors:
    _dio.interceptors.addAll([
      // A. Cache Interceptor
      DioCacheInterceptor(options: cacheOptions),

      // B. Auth Bearer Token Interceptor
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = getAuthToken();
          if (token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // Automatic 401 Refresh Token Handler:
          if (error.response?.statusCode == 401) {
            print('[Dio]: Intercepted 401 Unauthorized. Attempting refresh...');
            // Perform token refresh and retry request:
            // ...
          }
          return handler.next(error);
        },
      ),

      // C. Structured Logging Interceptor
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => print('[HTTP]: $obj'),
      ),
    ]);
  }
}
```

---

## 5. Canceling In-Flight Requests with `CancelToken`

When a user navigates away from a screen or types a new search query, cancel outstanding network requests immediately to save bandwidth and battery:

```dart
// lib/features/users/data/repositories/user_repository.dart
import 'package:dio/dio.dart';
import '../models/user_model.dart';

class UserRepository {
  final Dio _dio;
  CancelToken? _searchCancelToken;

  UserRepository(this._dio);

  Future<List<UserModel>> searchUsers(String query) async {
    // 1. Cancel previous pending search request:
    _searchCancelToken?.cancel('New search query submitted');
    _searchCancelToken = CancelToken();

    try {
      final response = await _dio.get(
        '/users/search',
        queryParameters: {'q': query},
        cancelToken: _searchCancelToken,
      );

      final dataList = response.data as List<dynamic>;
      return dataList
          .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        print('Search request was cancelled safely.');
        return [];
      }
      throw Exception('Network failed: ${e.message}');
    }
  }

  void dispose() {
    _searchCancelToken?.cancel('Repository disposed');
  }
}
```

---

## Troubleshooting & Best Practices

1. **Explicit Casts on Deserialized Lists**
   When parsing JSON arrays (`response.data as List`), use `(json as Map<String, dynamic>)` inside `.map()`. Dart's sound type system requires explicit map typing for `fromJson` constructors.

2. **Always Handle `DioException` by Type**
   Inspect `e.type`:

   - `DioExceptionType.connectionTimeout`: No internet / server unreachable.
   - `DioExceptionType.badResponse`: Server returned 4xx or 5xx status code.
   - `DioExceptionType.cancel`: Request was cancelled intentionally by `CancelToken`.
