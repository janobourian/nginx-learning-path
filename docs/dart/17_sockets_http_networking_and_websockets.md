# Module 17: Sockets, HTTP Networking, WebSockets & Shelf Microservices

**Track:** Dart — Language & VM Architecture  
**Category:** Network Engineering, TCP Sockets, WebSockets & HTTP Microservices

---

## 1. Low-Level TCP Sockets with `dart:io`

Dart provides direct access to native OS TCP sockets via **`ServerSocket`** and **`Socket`**:

```dart
// src/networking/tcp_echo_server.dart
import 'dart:io';
import 'dart:convert';

void main() async {
  // Bind TCP Server on port 4000:
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, 4000);
  print('TCP Server listening on port ${server.port}...');

  await for (final Socket client in server) {
    print('Client connected from ${client.remoteAddress.address}:${client.remotePort}');

    // Echo incoming data back to client:
    client
        .transform(utf8.decoder)
        .listen((message) {
          print('Received: $message');
          client.write('ECHO: $message');
        }, onDone: () {
          print('Client disconnected.');
          client.close();
        });
  }
}
```

---

## 2. Real-Time WebSockets Server & Client

WebSockets provide full-duplex, bidirectional communication over a single TCP connection:

```dart
// src/networking/websocket_server.dart
import 'dart:io';

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('WebSocket Server running at ws://localhost:8080/ws');

  final activeSockets = <WebSocket>[];

  await for (final HttpRequest req in server) {
    if (req.uri.path == '/ws') {
      // Upgrade HTTP Request to WebSocket Protocol:
      final socket = await WebSocketTransformer.upgrade(req);
      activeSockets.add(socket);
      print('WebSocket client connected. Total clients: ${activeSockets.length}');

      socket.listen(
        (data) {
          print('Broadcast message: $data');
          // Broadcast to all connected clients:
          for (final client in activeSockets) {
            client.add('[Broadcast]: $data');
          }
        },
        onDone: () {
          activeSockets.remove(socket);
          print('Client disconnected. Remaining: ${activeSockets.length}');
        },
      );
    } else {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
    }
  }
}
```

---

## 3. High-Performance Web Services with `Shelf` (`package:shelf`)

While `HttpServer` from `dart:io` is low-level, **`Shelf`** is Dart's standard, composable web server ecosystem (equivalent to Express in Node or Axum in Rust):

```yaml
# pubspec.yaml
dependencies:
  shelf: ^1.4.1
  shelf_router: ^1.1.4
  shelf_cors_headers: ^0.1.5
```

```dart
// bin/server.dart
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

// 1. Feature Router:
Router createApiRouter() {
  final router = Router();

  // Healthcheck endpoint
  router.get('/health', (Request req) {
    return Response.ok(
      jsonEncode({
        'status': 'healthy',
        'uptime_sec': ProcessInfo.currentRss,
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // Dynamic parameterized route:
  router.get('/api/users/<userId>', (Request req, String userId) {
    if (userId == '404') {
      return Response.notFound(jsonEncode({'error': 'User not found'}));
    }

    return Response.ok(
      jsonEncode({
        'id': userId,
        'name': 'Alice Chen',
        'role': 'Enterprise Architect',
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // JSON POST mutation endpoint:
  router.post('/api/users', (Request req) async {
    final bodyString = await req.readAsString();
    final dynamic data = jsonDecode(bodyString);

    return Response(
      HttpStatus.created,
      body: jsonEncode({'success': true, 'created': data}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

void main() async {
  final router = createApiRouter();

  // 2. Composable Middleware Pipeline:
  final handler = const Pipeline()
      .addMiddleware(logRequests())              // Request logging middleware
      .addMiddleware(corsHeaders())             // CORS headers middleware
      .addHandler(router.call);

  // 3. Bind HTTP Server:
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

  server.autoCompress = true; // Built-in Gzip/Deflate compression!

  print('🚀 Enterprise Shelf Server listening on http://${server.address.host}:${server.port}');
}
```

---

## 4. Modern HTTP Client with Connection Pooling

```dart
import 'dart:io';
import 'dart:convert';

class ResilientApiClient {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 10;

  Future<Map<String, dynamic>> fetchJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set('User-Agent', 'Dart-Enterprise-Client/1.0');
    request.headers.set('Accept', 'application/json');

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP Error: ${response.statusCode}', uri: uri);
    }

    final responseBody = await response.transform(utf8.decoder).join();
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
```

---

## Troubleshooting & Best Practices

1. **Always Set `server.autoCompress = true`**
   Enabling `autoCompress` on Dart `HttpServer` automatically Gzip-compresses JSON and HTML responses exceeding 1KB, reducing network bandwidth usage by up to 75%.

2. **Handle Socket Disconnections Gracefully**
   When writing to a TCP socket or WebSocket, the remote client may drop connection abruptly. Always catch `SocketException` to prevent unhandled exceptions from crashing your server isolate.
