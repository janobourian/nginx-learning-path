# Module 03: Low-Level Binary Memory Allocation & Protocol Architecture

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Systems Architecture, Binary Buffers & Low-Level Memory Management

---

## 1. The Cross-Runtime Binary Memory Hierarchy

In server-side JavaScript (Node, Deno, Bun), binary network and file I/O is managed through the ECMAScript **`ArrayBuffer`** and **`TypedArray`** standard:

```text
┌─────────────────────────────────────────────────────────────┐
│                 TypedArray Memory Architecture              │
├────────────────────┬────────────────────────────────────────┤
│ **`ArrayBuffer`**  │ Fixed-length contiguous block of raw   │
│                    │ binary memory bytes.                   │
├────────────────────┼────────────────────────────────────────┤
│ **`Uint8Array`**   │ View of buffer as 8-bit unsigned bytes │
│                    │ (0 to 255). (Standard across all runtimes)│
├────────────────────┼────────────────────────────────────────┤
│ **`DataView`**     │ Explicit endian-aware binary reader &  │
│                    │ writer at arbitrary byte offsets.      │
├────────────────────┼────────────────────────────────────────┤
│ **`Buffer`**       │ Node.js legacy subclass of `Uint8Array`│
│                    │ with extra helper methods.             │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Endianness & Binary Data Views (`DataView`)

When communicating over network sockets or reading binary file formats, byte order (Endianness) is critical:

- **Big-Endian (Network Byte Order)**: Most significant byte stored first (`0x12 0x34`).
- **Little-Endian (x86 / ARM CPU Order)**: Least significant byte stored first (`0x34 0x12`).

```javascript
// Allocate 8-byte ArrayBuffer:
const buffer = new ArrayBuffer(8);
const view = new DataView(buffer);

// Write Big-Endian 32-bit Integer at offset 0:
view.setUint32(0, 0x1A2B3C4D, false); // false = Big-Endian

// Write Little-Endian 16-bit Integer at offset 4:
view.setUint16(4, 0x5E6F, true); // true = Little-Endian
```

---

## 3. High-Performance Binary RPC Protocol Codec

Let's build a binary protocol encoder and decoder that runs across **Node, Deno, and Bun** with zero dependencies:

```javascript
// src/binary/rpc_protocol.js

export class RpcFrameCodec {
  static MAGIC_HEADER = 0x52504331; // 'RPC1' in ASCII (32-bit uint)

  /**

   * Encodes an RPC Message into binary frame:
   * [0..3]  Magic Byte Header (0x52504331) - 4 Bytes
   * [4..5]  Command ID (16-bit uint)       - 2 Bytes
   * [6]     Flags (Bitmask: 0x01 = Compressed, 0x02 = Encrypted) - 1 Byte
   * [7..10] Payload Length in Bytes         - 4 Bytes
   * [11..N] Payload UTF-8 Bytes
   */
  static encode(commandId, flags, payloadObject) {
    const jsonString = JSON.stringify(payloadObject);
    const payloadBytes = new TextEncoder().encode(jsonString);

    const totalLength = 11 + payloadBytes.byteLength;
    const arrayBuffer = new ArrayBuffer(totalLength);
    const view = new DataView(arrayBuffer);
    const byteView = new Uint8Array(arrayBuffer);

    // 1. Write Header:
    view.setUint32(0, this.MAGIC_HEADER, false); // Big-Endian
    view.setUint16(4, commandId, false);
    view.setUint8(6, flags);
    view.setUint32(7, payloadBytes.byteLength, false);

    // 2. Copy Payload bytes directly into buffer:
    byteView.set(payloadBytes, 11);

    return byteView;
  }

  /**

   * Decodes a binary frame:
   */
  static decode(uint8Array) {
    if (uint8Array.byteLength < 11) {
      throw new RangeError('Incomplete binary frame: Header too small');
    }

    const view = new DataView(
      uint8Array.buffer,
      uint8Array.byteOffset,
      uint8Array.byteLength
    );

    const magic = view.getUint32(0, false);
    if (magic !== this.MAGIC_HEADER) {
      throw new Error(`Invalid RPC Magic Header: 0x${magic.toString(16)}`);
    }

    const commandId = view.getUint16(4, false);
    const flags = view.getUint8(6);
    const payloadLength = view.getUint32(7, false);

    if (uint8Array.byteLength < 11 + payloadLength) {
      throw new RangeError('Truncated packet: Incomplete payload bytes');
    }

    // Zero-Copy Slice:
    const payloadSlice = uint8Array.subarray(11, 11 + payloadLength);
    const jsonString = new TextDecoder().decode(payloadSlice);
    const payload = JSON.parse(jsonString);

    return {
      commandId,
      flags,
      isCompressed: (flags & 0x01) !== 0,
      payload,
    };
  }
}
```

---

## 4. Zero-Copy Slicing with `subarray()` vs `slice()`

```javascript
const raw = new Uint8Array([10, 20, 30, 40, 50]);

// 1. subarray(): Creates a VIEW pointing to the exact same memory (Zero-Copy!):
const subView = raw.subarray(1, 4); // [20, 30, 40]
subView[0] = 99; // Mutates 'raw' at index 1!
console.log(raw[1]); // 99

// 2. slice(): Allocates a NEW ArrayBuffer and COPIES all bytes:
const clonedCopy = raw.slice(1, 4); // Cloned memory
```

---

## Troubleshooting & Best Practices

1. **Always Check `byteOffset` with `DataView`**
   When creating a `DataView` from a `Uint8Array` that was created via `subarray()`, always pass `uint8.buffer`, `uint8.byteOffset`, and `uint8.byteLength`. Otherwise, the `DataView` will read from index 0 of the entire underlying memory slab.

2. **Prefer `Uint8Array` Over Node `Buffer` in Cross-Runtime Code**
   `Uint8Array` is a standard ECMAScript global supported across Deno, Bun, Node, and Browsers. Use `Uint8Array` as your standard binary interchange type.
