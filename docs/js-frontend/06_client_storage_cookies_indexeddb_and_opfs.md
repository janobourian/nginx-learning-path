# Module 06: Client-Side Storage — Cookies, IndexedDB & Origin Private File System (OPFS)

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** Client Storage, IndexedDB & Origin Private File System

---

## 1. The Client-Side Storage Matrix

Modern web browsers provide multiple storage layers with drastically different performance, capacity, and security profiles:

| Storage API | Capacity Limit | Synchronous / Async | Data Types | Security / XSS Risk |
| :--- | :--- | :--- | :--- | :--- |
| **`localStorage`** | **~5 MB** | **Synchronous (Blocks UI!)** | String only | **High (Accessible by any XSS script!)** |
| **Cookies** | **~4 KB** | Synchronous | String only | **Secure if `HttpOnly; Secure; SameSite`** |
| **`IndexedDB`** | **Gigabytes (Up to 80% disk)** | **Asynchronous (Transactional)** | Objects, Blobs, Buffers | Sandboxed to Origin |
| **`OPFS` (Private File System)** | **Gigabytes** | **Fast Sync Access (in Worker)** | **Raw Binary Files** | **Native Performance for SQLite/WASM!** |

---

## 2. Hardened Cookies & CHIPS Partitioning

Cookies sent to the server must be protected against tampering and cross-site tracking:

```http
Set-Cookie: __Host-session=xyz987; Secure; HttpOnly; SameSite=Strict; Path=/; Partitioned; Max-Age=604800
```
- **`__Host-` Prefix**: Requires `Secure`, must be sent from HTTPS, and cannot be modified by subdomains.
- **`Partitioned` (CHIPS)**: Prevents third-party tracking across different top-level sites.

---

## 3. Large-Scale Structured Storage with IndexedDB

**IndexedDB** is an asynchronous, transactional, indexed object database built into all modern browsers.

### Native Promise-Based IndexedDB Wrapper:

```javascript
// src/storage/indexed_db.js
export class EnterpriseDb {
  constructor(dbName = 'AppDatabase', version = 1) {
    this.dbName = dbName;
    this.version = version;
    this.db = null;
  }

  async open() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, this.version);

      // Schema Migrations & Store Creation:
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains('projects')) {
          // Create store with 'id' primary key:
          const store = db.createObjectStore('projects', { keyPath: 'id' });
          // Create searchable indexes:
          store.createIndex('by_category', 'category', { unique: false });
          store.createIndex('by_updated', 'updatedAt', { unique: false });
        }
      };

      request.onsuccess = () => {
        this.db = request.result;
        resolve(this.db);
      };

      request.onerror = () => reject(request.error);
    });
  }

  async put(storeName, item) {
    const tx = this.db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    store.put(item);
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve(item);
      tx.onerror = () => reject(tx.error);
    });
  }

  async get(storeName, id) {
    const tx = this.db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);
    const req = store.get(id);
    return new Promise((resolve, reject) => {
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  async queryByIndex(storeName, indexName, value) {
    const tx = this.db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);
    const index = store.index(indexName);
    const req = index.getAll(value);
    return new Promise((resolve, reject) => {
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
}
```

---

## 4. Origin Private File System (OPFS) for Extreme I/O Performance

The **Origin Private File System (OPFS)** provides direct, private, sandboxed file system access with native OS disk performance (used by SQLite Wasm, Photoshop Web, and video editors):

```javascript
// src/storage/opfs_service.js

export async function writeBinaryToOpfs(fileName, arrayBufferData) {
  // 1. Get private root directory handle:
  const root = await navigator.storage.getDirectory();

  // 2. Create or open file:
  const fileHandle = await root.getFileHandle(fileName, { create: true });

  // 3. Create writable stream:
  const writable = await fileHandle.createWritable();
  await writable.write(arrayBufferData);
  await writable.close();

  console.log(`Successfully persisted ${arrayBufferData.byteLength} bytes to OPFS.`);
}

export async function readBinaryFromOpfs(fileName) {
  const root = await navigator.storage.getDirectory();
  const fileHandle = await root.getFileHandle(fileName);
  const file = await fileHandle.getFile();
  return await file.arrayBuffer();
}
```

### Ultra-Fast Synchronous File Access in Web Workers:
Inside a Web Worker, OPFS provides **`createSyncAccessHandle()`**, allowing WebAssembly and SQLite C libraries to read and write bytes with **microsecond synchronous NVMe speeds**:

```javascript
// Inside a Dedicated Web Worker:
const fileHandle = await root.getFileHandle('sqlite.db');
const accessHandle = await fileHandle.createSyncAccessHandle();

const buffer = new Uint8Array(1024);
// Direct in-place synchronous read:
const bytesRead = accessHandle.read(buffer, { at: 0 });

accessHandle.flush();
accessHandle.close();
```

---

## 5. Storage Quota & Persistence Management (`navigator.storage`)

Modern browsers may automatically purge temporary client storage if device disk space is low. 

Request **Persistent Storage** to prevent eviction:

```javascript
export async function ensurePersistentStorage() {
  if (navigator.storage && navigator.storage.persist) {
    const isPersisted = await navigator.storage.persisted();
    console.log(`Current persistence status: ${isPersisted}`);

    if (!isPersisted) {
      const granted = await navigator.storage.persist();
      console.log(`Persistent storage granted: ${granted}`);
    }

    // Inspect Quota:
    const { quota, usage } = await navigator.storage.estimate();
    console.log(`Used: ${(usage / 1024 / 1024).toFixed(2)} MB of ${(quota / 1024 / 1024).toFixed(2)} MB`);
  }
}
```

---

## Troubleshooting & Best Practices

1. **Never Store Large Payloads or Tokens in `localStorage`**
   `localStorage` operations are **100% synchronous and block the main JavaScript thread**. Reading a 4MB JSON string from `localStorage` freezes UI scrolling and frame rendering. Always use **IndexedDB** for data > 50KB.

2. **Always Handle `onversionchange` in IndexedDB**
   When a user opens multiple tabs and a new app version triggers a database upgrade, older tabs must listen to `db.onversionchange = () => db.close()` to prevent database locking errors.
