# Module 16: WebAssembly (WASM) Integration in Deno

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Performance & Cross-Language Interoperability

---

## WebAssembly in Deno

WebAssembly (WASM) is a binary instruction format that runs at near-native speed inside the JavaScript runtime. Unlike FFI (which loads external native libraries), WASM modules are sandboxed — they cannot access the filesystem, network, or OS directly unless you explicitly provide those capabilities through imports.

Deno supports WebAssembly natively because V8 (Deno's JavaScript engine) has full WASM support built in. The same WASM module that runs in a browser runs identically in Deno — same performance, same sandbox model.

### When to use WASM over FFI

- When you need cross-platform compatibility without platform-specific binaries
- When the native code must be sandboxed (untrusted computation)
- When you want to share code between browser and server
- For algorithms that benefit from WASM's linear memory model: image processing, audio codecs, parsers, compression

### When to use FFI instead

- When you need OS-level access (file descriptors, hardware)
- When the library requires dynamic linking to system libraries
- When startup time matters and the WASM module is very large

---

## Instantiating a WASM Module

```typescript
// Load and instantiate a WASM module from a local file
const wasmBytes = await Deno.readFile("./math_utils.wasm");
const wasmModule = new WebAssembly.Module(wasmBytes);
const wasmInstance = new WebAssembly.Instance(wasmModule);

// Access exported functions
const { add, multiply, fibonacci } = wasmInstance.exports as {
  add: (a: number, b: number) => number;
  multiply: (a: number, b: number) => number;
  fibonacci: (n: number) => number;
};

console.log(add(10, 32));         // 42
console.log(multiply(6, 7));      // 42
console.log(fibonacci(20));       // 6765
```

### Streaming Instantiation (Faster for Large Modules)

```typescript
// WebAssembly.instantiateStreaming compiles while downloading
// Works with fetch — the standard browser API
const response = await fetch("https://cdn.example.com/heavy-codec.wasm");
const { instance } = await WebAssembly.instantiateStreaming(response);

// Or from a local file using a custom stream
const file = await Deno.open("./codec.wasm");
const { instance: localInstance } = await WebAssembly.instantiateStreaming(
  new Response(file.readable)
);
```

---

## Compiling C to WASM with Emscripten

```c
// image_processor.c — image processing functions

#include <stdint.h>

#include <stdlib.h>

#include <string.h>

#include <math.h>

// Apply grayscale conversion to RGBA pixel data
void to_grayscale(uint8_t* pixels, int width, int height) {
    int total = width * height * 4;
    for (int i = 0; i < total; i += 4) {
        uint8_t r = pixels[i];
        uint8_t g = pixels[i + 1];
        uint8_t b = pixels[i + 2];
        // Luminosity formula: 0.299R + 0.587G + 0.114B
        uint8_t gray = (uint8_t)(0.299f * r + 0.587f * g + 0.114f * b);
        pixels[i] = gray;
        pixels[i + 1] = gray;
        pixels[i + 2] = gray;
        // Alpha channel (pixels[i+3]) remains unchanged
    }
}

// Apply Gaussian blur (simplified 3x3 kernel)
void gaussian_blur(uint8_t* src, uint8_t* dst, int width, int height) {
    // kernel: 1 2 1 / 2 4 2 / 1 2 1  (sum = 16)
    for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
            for (int c = 0; c < 3; c++) {
                int sum =
                    src[((y-1)*width + (x-1))*4 + c] * 1 +
                    src[((y-1)*width + x)    *4 + c] * 2 +
                    src[((y-1)*width + (x+1))*4 + c] * 1 +
                    src[(y*width + (x-1))    *4 + c] * 2 +
                    src[(y*width + x)        *4 + c] * 4 +
                    src[(y*width + (x+1))    *4 + c] * 2 +
                    src[((y+1)*width + (x-1))*4 + c] * 1 +
                    src[((y+1)*width + x)    *4 + c] * 2 +
                    src[((y+1)*width + (x+1))*4 + c] * 1;
                dst[(y*width + x)*4 + c] = (uint8_t)(sum / 16);
            }
            dst[(y*width + x)*4 + 3] = src[(y*width + x)*4 + 3];
        }
    }
}

// WASM memory allocation helper — called from JavaScript
void* alloc(size_t size) { return malloc(size); }
void dealloc(void* ptr) { free(ptr); }
```

```bash

# Compile C to WASM using Emscripten
emcc image_processor.c \
  -o image_processor.wasm \
  -O3 \
  -s WASM=1 \
  -s SIDE_MODULE=2 \
  -s EXPORTED_FUNCTIONS='["_to_grayscale","_gaussian_blur","_alloc","_dealloc"]' \
  --no-entry
```

```typescript
// image_processor_wasm.ts
interface ImageProcessorExports extends WebAssembly.Exports {
  to_grayscale: (pixelPtr: number, width: number, height: number) => void;
  gaussian_blur: (srcPtr: number, dstPtr: number, width: number, height: number) => void;
  alloc: (size: number) => number;
  dealloc: (ptr: number) => void;
  memory: WebAssembly.Memory;
}

const wasmBytes = await Deno.readFile("./image_processor.wasm");
const { instance } = await WebAssembly.instantiate(wasmBytes);
const exports = instance.exports as ImageProcessorExports;

export function grayscale(pixels: Uint8Array, width: number, height: number): Uint8Array {
  const size = pixels.length;
  const ptr = exports.alloc(size);

  try {
    // Copy JavaScript pixel data into WASM linear memory
    const wasmMemory = new Uint8Array(exports.memory.buffer);
    wasmMemory.set(pixels, ptr);

    // Run the C function (in WASM)
    exports.to_grayscale(ptr, width, height);

    // Copy result back to JavaScript
    return new Uint8Array(exports.memory.buffer, ptr, size).slice();
  } finally {
    exports.dealloc(ptr);  // Always free WASM memory
  }
}
```

---

## Compiling Rust to WASM with `wasm-pack`

Rust is the most ergonomic language for targeting WASM because `wasm-pack` handles the entire compilation pipeline:

```toml

# Cargo.toml
[package]
name = "json-validator"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wasm-bindgen = "0.2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

```rust
// src/lib.rs
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn validate_email(email: &str) -> bool {
    // Simple email validation — in production use a proper regex
    let at_pos = email.find('@');
    if let Some(at) = at_pos {
        let (local, domain) = (&email[..at], &email[at+1..]);
        !local.is_empty() && domain.contains('.') && !domain.starts_with('.')
    } else {
        false
    }
}

#[wasm_bindgen]
pub fn compress_text(input: &str) -> Vec<u8> {
    // Simple run-length encoding as an example
    let mut result = Vec::new();
    let bytes = input.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let current = bytes[i];
        let mut count = 1u8;
        while i + count as usize < bytes.len()
            && bytes[i + count as usize] == current
            && count < 255
        {
            count += 1;
        }
        result.push(count);
        result.push(current);
        i += count as usize;
    }
    result
}

#[wasm_bindgen]
pub fn levenshtein(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let m = a.len(); let n = b.len();
    let mut dp = vec![vec![0usize; n + 1]; m + 1];
    for i in 0..=m { dp[i][0] = i; }
    for j in 0..=n { dp[0][j] = j; }
    for i in 1..=m {
        for j in 1..=n {
            dp[i][j] = if a[i-1] == b[j-1] { dp[i-1][j-1] }
                       else { 1 + dp[i-1][j].min(dp[i][j-1]).min(dp[i-1][j-1]) };
        }
    }
    dp[m][n]
}
```

```bash

# Build WASM package targeting web (works in Deno too)
wasm-pack build --target web --out-dir ./pkg
```

```typescript
// Use the wasm-pack generated module in Deno
import init, { validate_email, levenshtein } from "./pkg/json_validator.js";

// Initialize the WASM module (loads and compiles the .wasm file)
await init();

console.log(validate_email("alice@example.com"));  // true
console.log(validate_email("not-an-email"));        // false
console.log(levenshtein("kitten", "sitting"));       // 3
```

---

## WASM Linear Memory Model

WASM modules have a flat, linear memory that grows in 64KB pages. JavaScript and WASM share this memory:

```typescript
const { instance } = await WebAssembly.instantiate(wasmBytes, {
  env: {
    // Provide memory to WASM (or let WASM create its own)
    memory: new WebAssembly.Memory({ initial: 256, maximum: 512 }),  // 16MB to 32MB
  },
});

const memory = instance.exports.memory as WebAssembly.Memory;
const view = new Uint8Array(memory.buffer);

// Write a string to WASM memory
function writeString(ptr: number, str: string): void {
  const bytes = new TextEncoder().encode(str + "\0");  // null-terminate
  view.set(bytes, ptr);
}

// Read a string from WASM memory
function readString(ptr: number): string {
  let end = ptr;
  while (view[end] !== 0) end++;
  return new TextDecoder().decode(view.slice(ptr, end));
}

// Memory grows if needed
if (memory.buffer.byteLength < needed) {
  memory.grow(Math.ceil((needed - memory.buffer.byteLength) / 65536));
}
```

---

## WASI — WebAssembly System Interface

WASI provides WASM modules with access to OS capabilities through a standardized interface:

```typescript
// Run a WASM module compiled with WASI target
import { WASI } from "https://deno.land/std@0.224.0/wasi/snapshot_preview1.ts";

const wasi = new WASI({
  args: Deno.args,
  env: Object.fromEntries(Object.entries(Deno.env.toObject())),
  preopens: {
    "/": "./sandbox",  // Map WASM's "/" to local "./sandbox" directory
  },
});

const wasmBytes = await Deno.readFile("./wasi_program.wasm");
const { instance } = await WebAssembly.instantiate(wasmBytes, {
  wasi_snapshot_preview1: wasi.exports,
});

wasi.start(instance);
```

---

## Troubleshooting

### `WebAssembly.instantiate()` throws `CompileError`

The `.wasm` file is corrupt, not a valid WASM binary, or targets a newer WASM feature set than V8 supports. Verify with `wasm-objdump -h ./module.wasm` (requires wabt tools) and check that it begins with the WASM magic bytes `0061736d`.

### WASM module runs but produces wrong results

Memory layout mismatch: the JavaScript side is writing to the wrong offset, or reading back the wrong number of bytes. Use `console.log(new Uint8Array(instance.exports.memory.buffer, ptr, 32))` to inspect raw memory around the pointer.

### Performance is slower than expected

WASM is fastest for compute-bound loops with minimal JS↔WASM boundary crossings. If you call a WASM function 10,000 times per frame passing individual numbers, the call overhead dominates. Instead, pass large buffers and have WASM process them in bulk.
