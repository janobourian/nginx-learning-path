# Module 13: Platform Channels, Pigeon & Type-Safe Native FFI

**Track:** Flutter — Multi-Platform Architecture & Impeller Engine
**Category:** Native Interop, Platform Channels & Type-Safe Pigeon Generators

---

## 1. How Flutter Communicates with Native iOS & Android

When a Flutter app needs access to platform-specific hardware or OS features (Bluetooth, Camera, Apple HealthKit, Android Biometrics, Battery Telemetry), it communicates across the **Platform Channel Architecture**:

```text
Platform Channel Architecture:
[Flutter Dart Framework]
        │
        ▼ (Binary Protocol: StandardMessageCodec serialization)
[Platform Channel Bridge (C++ Engine)]
        │
        ▼ (IPC Bridge across UI Thread)
[Host Platform: Swift / Objective-C (iOS) | Kotlin / Java (Android)]
        │
        ▼ (Native OS APIs)
[Hardware / Native SDKs: CoreBluetooth, CameraX, HealthKit]
```

---

## 2. The 3 Built-in Platform Channel Types

| Channel Type | Communication Model | Primary Use Case |
| :--- | :--- | :--- |
| **`MethodChannel`** | **Async Request-Response** (`invokeMethod`) | Fetching battery level, triggering biometric auth, saving to Keychain |
| **`EventChannel`** | **Continuous Reactive Stream** (`receiveBroadcastStream`) | Accelerometer sensor stream, GPS live location tracking |
| **`BasicMessageChannel`** | **Raw Binary / String / JSON Messages** | Custom binary codecs, image buffer streaming |

---

## 3. The Problem with Legacy `MethodChannel`

Traditional `MethodChannel` code is **stringly-typed and fragile**:

```dart
// ❌ Legacy MethodChannel:
final int battery = await channel.invokeMethod('getBattery', {'mode': 'fast'});
// 1. Typos in method name 'getBattery' only crash at runtime!
// 2. Data maps require manual dynamic casting: (res['level'] as int).
// 3. No compile-time type safety across Swift / Kotlin / Dart.
```

---

## 4. Type-Safe Platform Interop with Pigeon (`package:pigeon`)

**Pigeon** is Google's official code-generation tool for Flutter that generates **100% type-safe compile-time interfaces in Dart, Swift (iOS), and Kotlin (Android)** from a single schema definition!

```text
Pigeon Workflow:
[pigeons/battery_service.dart (Schema)]
                   │
                   ▼ (dart run pigeon)
 ┌─────────────────┼─────────────────┐
 ▼                 ▼                 ▼
[Generated Dart]  [Generated Swift]  [Generated Kotlin]
(Compile-Safe)    (Compile-Safe)     (Compile-Safe)
```

### 1. Defining the Pigeon Schema (`pigeons/battery_service.dart`)

```dart
// pigeons/battery_service.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/core/native/battery_service.g.dart',
  swiftOut: 'ios/Runner/BatteryService.g.swift',
  kotlinOut: 'android/app/src/main/kotlin/com/acme/app/BatteryService.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.acme.app'),
))
class BatteryInfo {
  final int percentage;
  final bool isCharging;
  final String thermalState;

  BatteryInfo({
    required this.percentage,
    required this.isCharging,
    required this.thermalState,
  });
}

@HostApi()
abstract class NativeBatteryApi {
  BatteryInfo getBatteryTelemetry();
  void triggerHapticFeedback(int intensity);
}
```

Run code generator:

```bash
dart run pigeon --input pigeons/battery_service.dart
```

---

### 2. Implementing the Host API in Swift (iOS: `ios/Runner/AppDelegate.swift`)

```swift
// ios/Runner/AppDelegate.swift
import UIKit
import Flutter

class BatteryApiImplementation: NativeBatteryApi {
  func getBatteryTelemetry() throws -> BatteryInfo {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = Int(UIDevice.current.batteryLevel * 100)
    let isCharging = UIDevice.current.batteryState == .charging

    return BatteryInfo(
      percentage: Int64(level),
      isCharging: isCharging,
      thermalState: "NOMINAL"
    )
  }

  func triggerHapticFeedback(intensity: Int64) throws {
    let impact = UIImpactFeedbackGenerator(style: .heavy)
    impact.impactOccurred()
  }
}

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

    // Register the Pigeon generated API:
    NativeBatteryApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: BatteryApiImplementation())

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

### 3. Consuming the Type-Safe API in Flutter Dart Code

```dart
// lib/features/battery/presentation/battery_screen.dart
import 'package:flutter/material.dart';
import '@/core/native/battery_service.g.dart';

class BatteryTelemetryScreen extends StatefulWidget {
  const BatteryTelemetryScreen({super.key});

  @override
  State<BatteryTelemetryScreen> createState() => _BatteryTelemetryScreenState();
}

class _BatteryTelemetryScreenState extends State<BatteryTelemetryScreen> {
  // Generated Pigeon API Client:
  final NativeBatteryApi _batteryApi = NativeBatteryApi();
  BatteryInfo? _info;

  Future<void> _refreshBattery() async {
    try {
      // 100% Type-Safe Method Invocation!
      final info = await _batteryApi.getBatteryTelemetry();
      setState(() {
        _info = info;
      });

      // Trigger native haptic feedback:
      await _batteryApi.triggerHapticFeedback(2);
    } catch (e) {
      print('Failed to read native battery telemetry: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native Pigeon Telemetry')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_info != null) ...[
              Text('Battery Level: ${_info!.percentage}%', style: const TextStyle(fontSize: 24)),
              Text('Charging: ${_info!.isCharging ? "⚡ Yes" : "No"}'),
              Text('Thermal State: ${_info!.thermalState}'),
            ] else ...[
              const Text('Tap below to read native OS hardware metrics'),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshBattery,
              child: const Text('Fetch Native Battery Metrics'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 5. Platform Channels vs Dart FFI Decision Matrix

| Metric / Dimension | Platform Channels (Pigeon) | Direct Native FFI (`dart:ffi`) |
| :--- | :--- | :--- |
| **Execution Thread** | Runs across Platform UI Thread | Runs **directly on the Dart thread / Isolate** |
| **Call Latency** | ~1 to 5 milliseconds (IPC Bridge) | **~2 nanoseconds** (Direct memory pointer call) |
| **Best For** | Accessing native OS APIs (UIKit, Android Services, Permissions) | High-performance C/C++/Rust computation (OpenCV, SQLite, WebRTC) |

---

## Troubleshooting & Best Practices

1. **Always Use Pigeon for New Native Plugins**
   Avoid writing manual `MethodChannel.invokeMethod` code. Pigeon generates type-safe schemas that catch missing parameters and interface mismatches during Xcode/Gradle compile time.

2. **Offload Heavy Platform Calls Off the UI Thread**
   On Android, standard platform channel calls run on the main UI thread. For long-running operations (e.g. native image filtering), dispatch the work to a background Kotlin Coroutine before returning the result to Pigeon.
