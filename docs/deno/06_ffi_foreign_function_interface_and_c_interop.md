# Module 06: FFI — Foreign Function Interface & C Interop

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Native Code Integration & Systems Programming

---

## What Is FFI and Why Use It?

The Foreign Function Interface (FFI) lets Deno call functions compiled in native languages — C, C++, Rust, Go — directly from TypeScript. This bridges the gap between JavaScript's convenience and the raw performance or OS-level capabilities that only native code provides.

Common use cases:
- **Image processing**: calling libvips or libpng for high-throughput image manipulation
- **Cryptography**: using OS-provided or hardware-accelerated crypto primitives
- **Database drivers**: calling SQLite's C library directly
- **Audio/video**: calling FFmpeg or libav
- **Hardware access**: reading from USB devices, GPIO pins, serial ports
- **Performance-critical algorithms**: numerical computing, compression

FFI requires `--allow-ffi` since it bypasses the Deno sandbox completely — native code runs with the process's full OS capabilities.

---

## How Deno FFI Works

`Deno.dlopen()` loads a shared library (`.so` on Linux, `.dylib` on macOS, `.dll` on Windows) and creates a typed interface to its exported functions. You describe the function signatures using Deno's type system, and Deno handles the marshaling of JavaScript values to C types and back.

```typescript
// Load a shared library and declare its function signatures
const lib = Deno.dlopen("./libmylib.so", {
  // Function name as exported from the C library
  add_numbers: {
    parameters: ["i32", "i32"],  // C types for arguments
    result: "i32",               // C type for return value
  },
  compute_hash: {
    parameters: ["pointer", "usize"],  // pointer to buffer, length
    result: "u64",
  },
});

// Call the native function — it executes at native speed
const sum = lib.symbols.add_numbers(40, 2);
console.log(sum);  // 42

lib.close();  // Release the library
```

---

## Supported Native Types

| Deno FFI Type | C Equivalent | JavaScript Value |
|---|---|---|
| `"i8"` | `int8_t` / `char` | Number |
| `"i16"` | `int16_t` / `short` | Number |
| `"i32"` | `int32_t` / `int` | Number |
| `"i64"` | `int64_t` / `long` | BigInt |
| `"u8"` | `uint8_t` / `unsigned char` | Number |
| `"u16"` | `uint16_t` | Number |
| `"u32"` | `uint32_t` | Number |
| `"u64"` | `uint64_t` | BigInt |
| `"f32"` | `float` | Number |
| `"f64"` | `double` | Number |
| `"bool"` | `bool` | Boolean |
| `"pointer"` | `void*` / `char*` | Pointer / null |
| `"buffer"` | `uint8_t*` | Uint8Array |
| `"usize"` | `size_t` | Number / BigInt |
| `"void"` | `void` | undefined |

---

## Practical Example: Calling SQLite via FFI

Rather than using the `npm:better-sqlite3` package, you can call SQLite's C API directly:

```c
// sqlite_wrapper.c — compiled to libsqlite_wrapper.so
#include <sqlite3.h>
#include <string.h>
#include <stdlib.h>

typedef struct {
    sqlite3* db;
} Database;

Database* db_open(const char* path) {
    Database* wrapper = malloc(sizeof(Database));
    sqlite3_open(path, &wrapper->db);
    return wrapper;
}

int db_exec(Database* wrapper, const char* sql) {
    char* errMsg = NULL;
    int rc = sqlite3_exec(wrapper->db, sql, NULL, NULL, &errMsg);
    if (errMsg) sqlite3_free(errMsg);
    return rc;
}

void db_close(Database* wrapper) {
    sqlite3_close(wrapper->db);
    free(wrapper);
}
```

```bash
# Compile the wrapper
gcc -shared -fPIC -o libsqlite_wrapper.so sqlite_wrapper.c -lsqlite3
```

```typescript
// sqlite_ffi.ts
const lib = Deno.dlopen("./libsqlite_wrapper.so", {
  db_open: {
    parameters: ["buffer"],
    result: "pointer",
  },
  db_exec: {
    parameters: ["pointer", "buffer"],
    result: "i32",
  },
  db_close: {
    parameters: ["pointer"],
    result: "void",
  },
});

function openDatabase(path: string): Deno.PointerValue {
  const pathBytes = new TextEncoder().encode(path + "\0"); // null-terminate
  return lib.symbols.db_open(pathBytes);
}

function execSQL(db: Deno.PointerValue, sql: string): number {
  const sqlBytes = new TextEncoder().encode(sql + "\0");
  return lib.symbols.db_exec(db, sqlBytes) as number;
}

function closeDatabase(db: Deno.PointerValue): void {
  lib.symbols.db_close(db);
}

// Usage
const db = openDatabase("./mydata.db");
execSQL(db, "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");
execSQL(db, "INSERT INTO users (name) VALUES ('Alice')");
closeDatabase(db);
```

---

## Practical Example: Calling a Rust Library

Rust is the most ergonomic choice for writing FFI-callable libraries because it compiles to C-compatible shared libraries with `#[no_mangle]` and `extern "C"`.

```rust
// src/lib.rs — Rust library compiled to cdylib
use std::ffi::CStr;
use std::os::raw::c_char;

/// Compute the Levenshtein distance between two C strings.
/// Returns -1 if either string is null.
#[no_mangle]
pub extern "C" fn levenshtein_distance(a: *const c_char, b: *const c_char) -> i32 {
    if a.is_null() || b.is_null() {
        return -1;
    }
    let a = unsafe { CStr::from_ptr(a) }.to_string_lossy();
    let b = unsafe { CStr::from_ptr(b) }.to_string_lossy();
    compute_distance(&a, &b) as i32
}

fn compute_distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let m = a.len();
    let n = b.len();
    let mut dp = vec![vec![0usize; n + 1]; m + 1];
    for i in 0..=m { dp[i][0] = i; }
    for j in 0..=n { dp[0][j] = j; }
    for i in 1..=m {
        for j in 1..=n {
            dp[i][j] = if a[i-1] == b[j-1] {
                dp[i-1][j-1]
            } else {
                1 + dp[i-1][j].min(dp[i][j-1]).min(dp[i-1][j-1])
            };
        }
    }
    dp[m][n]
}
```

```toml
# Cargo.toml
[package]
name = "string_utils"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
```

```bash
cargo build --release
# Produces: target/release/libstring_utils.dylib (macOS) or .so (Linux)
```

```typescript
// string_utils_ffi.ts
const libSuffix = Deno.build.os === "darwin" ? "dylib" : "so";
const lib = Deno.dlopen(
  `./target/release/libstring_utils.${libSuffix}`,
  {
    levenshtein_distance: {
      parameters: ["buffer", "buffer"],
      result: "i32",
    },
  }
);

function levenshteinDistance(a: string, b: string): number {
  const encoder = new TextEncoder();
  const aBuf = encoder.encode(a + "\0");
  const bBuf = encoder.encode(b + "\0");
  return lib.symbols.levenshtein_distance(aBuf, bBuf) as number;
}

console.log(levenshteinDistance("kitten", "sitting"));  // 3
console.log(levenshteinDistance("saturday", "sunday"));  // 3
```

---

## Async FFI Callbacks

For non-blocking native calls, Deno supports marking FFI functions as non-blocking. The call returns a Promise that resolves when the native function completes on a thread pool:

```typescript
const lib = Deno.dlopen("./libcompute.so", {
  expensive_computation: {
    parameters: ["u64"],
    result: "u64",
    // nonblocking: true means Deno will call this on a separate thread
    // and return a Promise, not blocking the event loop
    nonblocking: true,
  },
});

// This doesn't block the JavaScript event loop
const result = await lib.symbols.expensive_computation(1_000_000n);
console.log("Result:", result);
```

---

## Safety Considerations

FFI bypasses all Deno sandbox protections. Native code:
- Can read and write any memory in the process
- Can make any system calls
- Can crash the entire Deno process with a segfault
- Can access any file, network, or device regardless of Deno permission flags

Best practices:
1. Only load libraries you compiled yourself or from trusted, audited sources
2. Always null-check pointers before dereferencing
3. Use Rust or C++ with bounds checking rather than raw C where possible
4. Write thin wrappers that validate inputs before passing to native code
5. Use `--allow-ffi=./libmylib.so` (path-restricted) rather than `--allow-ffi` (global)

```bash
# Restrict FFI to a specific library path only
deno run --allow-ffi=./target/release/libstring_utils.dylib main.ts
```

---

## Troubleshooting

**`Error: permission denied: Deno.dlopen()`**

Add `--allow-ffi` or `--allow-ffi=./path/to/lib.so` to your run command.

**`Error: cannot open shared object file: No such file or directory`**

The library file doesn't exist at the specified path. Use an absolute path or ensure the relative path is correct from the process working directory.

**`TypeError: lib.symbols.my_func is not a function`**

The function name in the `Deno.dlopen` definition doesn't match the exported symbol name in the compiled library. Run `nm -D libmylib.so | grep my_func` to list actual exported symbols.

**Process segfaults when calling FFI function**

You are passing incorrect data types or null pointers. Check that:
- String arguments are null-terminated (`str + "\0"`)
- Buffer lengths match actual buffer sizes
- Pointer types are correctly defined
- The library's calling convention is C (`extern "C"` in Rust/C++)
