# Module 16: File System I/O, Web Streams & Binary Typed Data

**Track:** Dart — Language & VM Architecture
**Category:** Systems I/O, Binary Protocols & Typed Memory Buffers

---

## 1. File System Engineering with `dart:io`

Dart's **`dart:io`** library provides non-blocking, asynchronous file system APIs built directly on top of OS system calls (`epoll` on Linux, `kqueue` on macOS, and `IOCP` on Windows):

```dart
import 'dart:io';
import 'dart:convert';

Future<void> main() async {
  final configFile = File('config/server.json');

  // 1. Check if file exists asynchronously:
  if (!await configFile.exists()) {
    print('Config file not found. Creating default configuration...');
    // Create directory tree if missing:
    await configFile.parent.create(recursive: true);

    // Write file with atomic sync mode:
    await configFile.writeAsString(
      jsonEncode({'host': '127.0.0.1', 'port': 8080}),
      mode: FileMode.write,
      flush: true, // Force flush to physical disk hardware
    );
  }

  // 2. Read entire file into string:
  final contents = await configFile.readAsString();
  print('Loaded config: $contents');
}
```

---

## 2. High-Performance Streaming for Large Files

Reading a 10GB file into memory with `readAsBytes()` will immediately trigger an Out-Of-Memory (OOM) crash.

Use **Streams** to process files chunk-by-chunk with bounded memory:

```dart
import 'dart:io';
import 'dart:convert';

Future<void> processLargeLogFile(String inputPath, String outputPath) async {
  final inputFile = File(inputPath);
  final outputFile = File(outputPath);

  final sink = outputFile.openWrite(mode: FileMode.write);

  int lineCount = 0;
  int errorCount = 0;

  // Stream pipeline: Read Bytes -> Decode UTF-8 -> Split Lines
  await inputFile
      .openRead() // Stream<List<int>>
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        lineCount++;
        if (line.contains('[ERROR]')) {
          errorCount++;
          sink.writeln('[$lineCount] $line');
        }
      });

  await sink.flush();
  await sink.close();

  print('Processed $lineCount lines. Extracted $errorCount errors to $outputPath');
}
```

---

## 3. Binary Typed Data (`dart:typed_data`)

The **`dart:typed_data`** library provides high-performance, contiguous byte buffers mapped directly to memory without object boxing overhead.

```text
┌─────────────────────────────────────────────────────────────┐
│                    Typed Data Hierarchy                     │
├────────────────────┬────────────────────────────────────────┤
│ **`ByteBuffer`**   │ The raw block of contiguous memory     │
│                    │ bytes.                                 │
├────────────────────┼────────────────────────────────────────┤
│ **`Uint8List`**    │ View of buffer as 8-bit unsigned bytes │
├────────────────────┼────────────────────────────────────────┤
│ **`Int32List`**    │ View of buffer as 32-bit signed ints   │
├────────────────────┼────────────────────────────────────────┤
│ **`Float64List`**  │ View of buffer as 64-bit IEEE floats   │
├────────────────────┼────────────────────────────────────────┤
│ **`ByteData`**     │ Explicit endian-aware binary reader /  │
│                    │ writer view at arbitrary byte offsets. │
└────────────────────┴────────────────────────────────────────┘
```

```dart
import 'dart:typed_data';

void main() {
  // Allocate 1,000,000 8-bit integers (Exact 1 MB memory footprint!):
  final byteBuffer = Uint8List(1024 * 1024);

  // Set first byte:
  byteBuffer[0] = 0xFF; // 255
  print('Allocated ${byteBuffer.lengthInBytes} bytes');
}
```

---

## 4. Packing Binary Network Packets with `ByteData`

Let's design and parse a binary packet protocol header:

```text
Binary Protocol Header Format (12 Bytes Total):
[0..3]   Magic Number (0xDEADBEEF) - 32-bit uint
[4..5]   Protocol Version (e.g. 1) - 16-bit uint
[6..7]   Message Type ID (e.g. 42) - 16-bit uint
[8..11]  Payload Length in Bytes   - 32-bit uint
```

```dart
import 'dart:typed_data';

class PacketHeader {
  static const int magicNumber = 0xDEADBEEF;

  final int version;
  final int messageTypeId;
  final int payloadLength;

  PacketHeader({
    required this.version,
    required this.messageTypeId,
    required this.payloadLength,
  });

  // Serialize to 12 raw bytes:
  Uint8List toBytes() {
    final bytes = Uint8List(12);
    final data = ByteData.sublistView(bytes);

    // Write big-endian network byte order:
    data.setUint32(0, magicNumber, Endian.big);
    data.setUint16(4, version, Endian.big);
    data.setUint16(6, messageTypeId, Endian.big);
    data.setUint32(8, payloadLength, Endian.big);

    return bytes;
  }

  // Deserialize from 12 raw bytes:
  factory PacketHeader.fromBytes(Uint8List rawBytes) {
    if (rawBytes.length < 12) {
      throw FormatException('Packet header must be at least 12 bytes.');
    }

    final data = ByteData.sublistView(rawBytes);

    final magic = data.getUint32(0, Endian.big);
    if (magic != magicNumber) {
      throw FormatException('Invalid magic number: 0x${magic.toRadixString(16)}');
    }

    final version = data.getUint16(4, Endian.big);
    final messageType = data.getUint16(6, Endian.big);
    final length = data.getUint32(8, Endian.big);

    return PacketHeader(
      version: version,
      messageTypeId: messageType,
      payloadLength: length,
    );
  }
}

void main() {
  final header = PacketHeader(version: 2, messageTypeId: 104, payloadLength: 4096);
  final binaryPayload = header.toBytes();

  print('Serialized binary packet header (12 bytes):');
  print(binaryPayload);

  final parsed = PacketHeader.fromBytes(binaryPayload);
  print('Parsed Header: Version=${parsed.version}, Type=${parsed.messageTypeId}, Length=${parsed.payloadLength}B');
}
```

---

## Troubleshooting & Best Practices

1. **Always Specify Endianness in Network Protocols**
   Network protocols (TCP, UDP) standardly use **`Endian.big` (Network Byte Order)**. CPU architectures (ARM64, x86_64) typically store memory in `Endian.little`. Always explicitly pass `Endian.big` to `ByteData` methods to guarantee cross-platform protocol compatibility.

2. **Use `flush: true` for Critical Writes**
   When persisting audit logs or database transactions, always specify `flush: true` to force the OS file system buffer to flush data to physical non-volatile storage hardware.
