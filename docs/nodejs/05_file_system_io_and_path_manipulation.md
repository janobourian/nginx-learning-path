# Module 05: File System Architecture, POSIX FileHandles & Atomic Operations

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** File System Engineering, POSIX System Calls & Path Resolution

---

## 1. The 3 `node:fs` APIs

Node.js provides three separate APIs for interacting with the file system:

```text
┌─────────────────────────────────────────────────────────────┐
│                     The 3 `node:fs` Paradigms               │
├────────────────────┬────────────────────────────────────────┤
│ **1. Promise API** │ **`import fs from 'node:fs/promises'`**│
│                    │ - Non-blocking async/await.            │
│                    │ - Recommended for 99% of code.         │
├────────────────────┼────────────────────────────────────────┤
│ **2. Stream API**  │ **`fs.createReadStream()`**            │
│                    │ - Constant bounded memory for huge I/O.│
├────────────────────┼────────────────────────────────────────┤
│ **3. Sync API**    │ **`fs.readFileSync()`**                │
│                    │ - **Blocks the entire main thread!**   │
│                    │ - Only acceptable during app startup.  │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Low-Level POSIX File Handles (`fs.open`)

For high-performance systems (databases, log appenders), opening and closing a file for every read/write causes massive OS kernel context-switching overhead.

Use **`fsPromises.open()`** to maintain a persistent **`FileHandle`**:

```javascript
// src/storage/append_log.js
import fs from 'node:fs/promises';
import { Buffer } from 'node:buffer';

export class BinaryAppendLog {
  constructor(filePath) {
    this.filePath = filePath;
    this.handle = null;
  }

  async init() {
    // Open file in append mode ('a+'):
    this.handle = await fs.open(this.filePath, 'a+');
  }

  async appendRecord(dataString) {
    if (!this.handle) throw new Error('Log not initialized');

    const buffer = Buffer.from(`${new Date().toISOString()} ${dataString}\n`, 'utf8');

    // Write buffer directly to file descriptor:
    await this.handle.write(buffer);

    // Force flush data from OS page cache directly to physical disk (fsync):
    await this.handle.sync();
  }

  async close() {
    if (this.handle) {
      await this.handle.close();
      this.handle = null;
    }
  }
}
```

---

## 3. Atomic File Writes (Preventing Corrupted State on Server Crashes)

If your server crashes or loses power in the middle of `fs.writeFile('state.json', data)`, the file on disk will be left half-written and corrupt.

### The Atomic Write Pattern

1. Write the payload to a temporary file (`state.json.tmp_12345`).
2. Flush to disk (`handle.sync()`).
3. Atomically **rename** the temporary file over the target file using **`fs.rename()`**.
4. In POSIX file systems (Linux/macOS), `rename(2)` is an **atomic OS kernel operation**: the file is either 100% updated or 100% untouched; it can never be left in a corrupted intermediate state!

```javascript
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

export async function writeAtomicJson(filePath, dataObject) {
  const serialized = JSON.stringify(dataObject, null, 2);
  const tempPath = `${filePath}.tmp_${crypto.randomUUID()}`;

  // 1. Write to temporary file:
  const handle = await fs.open(tempPath, 'w');
  try {
    await handle.writeFile(serialized, 'utf8');
    await handle.sync(); // Force disk write
  } finally {
    await handle.close();
  }

  // 2. Atomic POSIX rename over target file:
  await fs.rename(tempPath, filePath);
}
```

---

## 4. Recursive Directory Traversal (`withFileTypes`)

When reading directories, use **`withFileTypes: true`** to avoid making extra `fs.stat()` system calls for every file:

```javascript
import fs from 'node:fs/promises';
import path from 'node:path';

export async function scanDirectoryRecursive(dirPath) {
  const results = [];
  // 'withFileTypes: true' returns Dirent objects with isDirectory() without extra syscalls!
  const entries = await fs.readdir(dirPath, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      const nested = await scanDirectoryRecursive(fullPath);
      results.push(...nested);
    } else if (entry.isFile()) {
      results.push(fullPath);
    }
  }

  return results;
}
```

---

## 5. Path Manipulation Mastery (`node:path`)

```javascript
import path from 'node:path';

// 1. path.join: Joins segments with OS-correct separator (/ on POSIX, \ on Windows)
const joined = path.join('/usr', 'local', 'bin', 'node'); // '/usr/local/bin/node'

// 2. path.resolve: Resolves relative path against current working directory to absolute path
const absolute = path.resolve('config', 'app.json'); // '/Users/admin/project/config/app.json'

// 3. path.parse: Splits path into root, dir, base, ext, name
const parsed = path.parse('/var/log/nginx/access.log');
// Output: { root: '/', dir: '/var/log/nginx', base: 'access.log', ext: '.log', name: 'access' }

// 4. path.relative: Solves relative jump between two absolute paths:
const rel = path.relative('/app/src/features', '/app/assets/images');
// Output: '../../assets/images'
```

---

## Troubleshooting & Best Practices

1. **`fs.watch` vs `fs.watchFile`**

   - **`fs.watch`**: Uses OS kernel event notifications (`inotify` on Linux, `FSEvents` on macOS). Ultra-fast, near-zero CPU usage.
   - **`fs.watchFile`**: Polls the file stat every few seconds. High CPU usage. Never use `fs.watchFile` in production!

2. **Always Use `path.join` and `path.resolve`**
   Never manually concatenate paths with strings (`dir + '/' + file`). String concatenation fails on Windows and creates security vulnerabilities (Path Traversal attacks).
