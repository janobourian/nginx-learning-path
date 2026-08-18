# Module 10: Systems File I/O, Advisory File Locks & Memory-Mapped Storage

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Systems Programming, File Locking & High-Performance I/O

---

## 1. POSIX System Calls & File Descriptors

When an application performs file I/O, it interfaces with the OS kernel through **File Descriptors (Integer handles)**:

```
┌─────────────────────────────────────────────────────────────┐
│                 POSIX File System System Calls              │
├────────────────────┬────────────────────────────────────────┤
│ **`open(2)`**      │ Allocates file descriptor and sets mode│
│                    │ (`O_RDWR`, `O_CREAT`, `O_APPEND`).     │
├────────────────────┼────────────────────────────────────────┤
│ **`fsync(2)`**     │ Flushes data AND metadata from OS page │
│                    │ cache to physical storage hardware.    │
├────────────────────┼────────────────────────────────────────┤
│ **`fdatasync(2)`** │ Flushes data only (Skips updating      │
│                    │ file modified timestamp for speed!).   │
├────────────────────┼────────────────────────────────────────┤
│ **`flock(2)`**     │ Places advisory lock across OS processes│
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Multi-Process Advisory File Locking

When multiple clustered worker processes write to the same shared state or append-only log file simultaneously, uncoordinated writes will corrupt binary records.

### Implementing an Advisory File Lock:

```javascript
// src/storage/file_lock.js
import fs from 'node:fs/promises';
import path from 'node:path';

export class AdvisoryFileLock {
  constructor(filePath, staleTimeoutMs = 10000) {
    this.lockPath = `${filePath}.lock`;
    this.staleTimeout = staleTimeoutMs;
  }

  async acquire(maxRetries = 20, retryDelayMs = 100) {
    for (let i = 0; i < maxRetries; i++) {
      try {
        // 'wx' flag: Open for writing, but FAILS if file already exists (Atomic OS check!):
        const handle = await fs.open(this.lockPath, 'wx');
        await handle.writeFile(JSON.stringify({ pid: process.pid, time: Date.now() }));
        await handle.close();
        return true; // Lock acquired!
      } catch (err) {
        if (err.code === 'EEXIST') {
          // Check if lock file is stale (crashed process):
          await this._cleanStaleLock();
          await new Promise((r) => setTimeout(r, retryDelayMs));
        } else {
          throw err;
        }
      }
    }
    throw new Error(`Failed to acquire lock for ${this.lockPath} after retries.`);
  }

  async release() {
    try {
      await fs.unlink(this.lockPath);
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
  }

  async _cleanStaleLock() {
    try {
      const stats = await fs.stat(this.lockPath);
      if (Date.now() - stats.mtimeMs > this.staleTimeout) {
        console.warn(`[FileLock]: Removing stale lock left by dead process: ${this.lockPath}`);
        await fs.unlink(this.lockPath);
      }
    } catch {}
  }
}
```

---

## 3. Atomic Directory Swapping for Zero-Downtime Deployments

To update static assets or ML model weights without dropping requests in the middle of a read:

```javascript
// src/deployment/atomic_deploy.js
import fs from 'node:fs/promises';
import path from 'node:path';

export async function deployNewAssetVersion(newVersionDir) {
  const currentSymlink = path.resolve('public/live');
  const tempSymlink = path.resolve(`public/live_tmp_${Date.now()}`);

  // 1. Create temporary symlink pointing to new version:
  await fs.symlink(newVersionDir, tempSymlink);

  // 2. Atomically rename symlink over current live link:
  // In POSIX systems, rename() is atomic! Requests switch to new version instantaneously.
  await fs.rename(tempSymlink, currentSymlink);

  console.log(`[Deploy]: Atomically switched live symlink to ${newVersionDir}`);
}
```

---

## Troubleshooting & Best Practices

1. **Always Use `fdatasync()` for High-Performance Databases**
   Calling `fsync()` writes both the file contents and updates the file modification timestamp in filesystem inode tables (two separate disk operations). `fdatasync()` writes only data bytes, reducing SSD write amplification by 50%.

2. **Clean Up Lockfiles in `finally` Blocks**
   Always wrap file operations guarded by file locks in `try ... finally { await lock.release(); }` to prevent abandoned lockfiles on unexpected exceptions.
