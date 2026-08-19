# Module 16: Local Persistence — `SharedPreferences`, `SecureStorage`, `Hive` & `SQLite`

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** Data Storage, SQLite, Key-Value Stores & Hardware Encryption

---

## 1. The Local Storage Decision Matrix

Flutter applications require different persistence strategies depending on data complexity, security, and read/write frequency:

| Storage Solution | Underlying Technology | Best Used For | Encryption Support |
| :--- | :--- | :--- | :--- |
| **`shared_preferences`** | NSUserDefaults (iOS) / SharedPreferences (Android) / LocalStorage (Web) | Light app preferences (Theme mode, onboarding boolean, language) | No (Plaintext) |
| **`flutter_secure_storage`** | **Apple Keychain (iOS) / Android KeyStore & EncryptedSharedPreferences** | **JWT Session Tokens, OAuth Refresh Tokens, API Secrets** | **Hardware-Backed AES Encryption** |
| **`hive_ce` (Hive)** | Pure Dart Binary Box Format | Ultra-fast NoSQL key-value cache, offline catalogs, fast key lookups | Optional AES-256 |
| **`sqflite` / `drift`** | Native SQLite Engine | Complex relational data (foreign keys, full-text search, ACID transactions) | Optional SQLCipher |

---

## 2. Secure Hardware Storage (`flutter_secure_storage`)

For sensitive authentication tokens and credentials:

```yaml

# pubspec.yaml
dependencies:
  flutter_secure_storage: ^9.0.0
```

```dart
// lib/core/storage/secure_token_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStorage {
  // Configure hardware encryption options:
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _tokenKey = 'auth_jwt_token';
  static const _refreshKey = 'auth_refresh_token';

  Future<void> saveTokens({required String token, required String refreshToken}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> clearAllTokens() async {
    await _storage.deleteAll();
  }
}
```

---

## 3. Ultra-Fast Binary NoSQL Storage with `Hive`

**Hive** is a lightweight, blazing-fast key-value database written in pure Dart. Because it is written in pure Dart without native C SQLite bindings, it runs identically across Mobile, Desktop, and Web:

```yaml

# pubspec.yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0

dev_dependencies:
  hive_generator: ^2.0.1
  build_runner: ^2.4.9
```

### 1. Defining a Hive Model & TypeAdapter

```dart
// lib/features/cache/models/cached_project.dart
import 'package:hive/hive.dart';

part 'cached_project.g.dart';

@HiveType(typeId: 1) // Unique Type ID
class CachedProject extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final double budget;

  @HiveField(3)
  final DateTime updatedAt;

  CachedProject({
    required this.id,
    required this.name,
    required this.budget,
    required this.updatedAt,
  });
}
```

### 2. Initializing & Querying Hive Boxes

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/cache/models/cached_project.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive on local disk:
  await Hive.initFlutter();

  // 2. Register generated TypeAdapter:
  Hive.registerAdapter(CachedProjectAdapter());

  // 3. Open Box:
  final projectBox = await Hive.openBox<CachedProject>('projects_box');

  // Insert or Update in Box:
  await projectBox.put(
    'p_101',
    CachedProject(
      id: 'p_101',
      name: 'Global Edge Expansion',
      budget: 150000.0,
      updatedAt: DateTime.now(),
    ),
  );

  // Read from Box:
  final project = projectBox.get('p_101');
  print('Retrieved from Hive: ${project?.name} (\$${project?.budget})');

  runApp(const MyApp());
}
```

---

## 4. Relational Storage with SQLite (`sqflite`)

When you need SQL queries (`SELECT ... WHERE ... JOIN`), transactions, and indexed searches:

```yaml

# pubspec.yaml
dependencies:
  sqflite: ^2.3.3+1
  path: ^1.9.0
```

```dart
// lib/core/storage/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('enterprise_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        customer_email TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('CREATE INDEX idx_orders_email ON orders (customer_email);');
  }

  Future<void> insertOrder(Map<String, dynamic> orderRow) async {
    final db = await instance.database;
    await db.insert(
      'orders',
      orderRow,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> queryOrdersByCustomer(String email) async {
    final db = await instance.database;
    return await db.query(
      'orders',
      where: 'customer_email = ?',
      whereArgs: [email],
      orderBy: 'created_at DESC',
    );
  }
}
```

---

## Troubleshooting & Best Practices

1. **`WidgetsFlutterBinding.ensureInitialized()` is Mandatory**
   When invoking asynchronous platform channels in `main()` before `runApp()` (such as `await Hive.initFlutter()` or `await SharedPreferences.getInstance()`), you **must** call `WidgetsFlutterBinding.ensureInitialized()` first.

2. **Never Store Passwords or Tokens in `SharedPreferences`**
   `SharedPreferences` writes data in unencrypted XML/plist files on disk, which are easily extracted from rooted/jailbroken devices. Always use **`flutter_secure_storage`** for credentials.
