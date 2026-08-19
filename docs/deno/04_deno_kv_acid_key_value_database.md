# Module 04: Deno KV — ACID Key-Value Database

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Built-In Persistence & Distributed State

---

## What Is Deno KV?

Deno KV is a built-in key-value database available in every Deno runtime. It requires no dependencies, no Docker container, and no separate database process. You call `Deno.openKv()` and you have a persistent, transactional store.

On local development it uses SQLite as the storage backend. On Deno Deploy (Deno's managed edge platform) it uses FoundationDB — a distributed database developed at Apple — providing the same ACID guarantees across globally replicated edge nodes.

This means: the same code that runs with an in-process SQLite database locally also runs at the edge of a globally distributed cluster, without changing a single line of code.

---

## Opening a KV Store

```typescript
// Open the default KV store (stored at a platform-defined path)
const kv = await Deno.openKv();

// Open a specific SQLite file (local development)
const kv = await Deno.openKv("./data.db");

// In-memory only (no persistence — useful for testing)
const kv = await Deno.openKv(":memory:");

// Always close when done to release the file handle
kv.close();
```

---

## Keys and Values

KV keys are arrays of **key parts**. Each part can be a string, number, boolean, Uint8Array, or bigint. The key `["users", "alice", "profile"]` is hierarchical: you can list all keys with prefix `["users"]` or `["users", "alice"]`.

Values can be any structured-serializable JavaScript value: strings, numbers, booleans, Arrays, plain objects, `Uint8Array`, `Date`, `Map`, `Set`, `RegExp`, and `bigint`. Functions, class instances with methods, and circular references are not serializable.

```typescript
const kv = await Deno.openKv();

// Set a value
await kv.set(["users", "alice"], {
  name: "Alice Chen",
  email: "alice@example.com",
  role: "admin",
  createdAt: new Date(),
});

// Get a value
const result = await kv.get<{ name: string; role: string }>(["users", "alice"]);

if (result.value === null) {
  console.log("Key does not exist");
} else {
  console.log(result.value.name);   // "Alice Chen"
  console.log(result.versionstamp); // "000000000000000a0000" — monotonic version
}

// Delete a key
await kv.delete(["users", "alice"]);
```

---

## Listing Keys with Ranges and Prefixes

```typescript
const kv = await Deno.openKv();

// Seed some data
await kv.set(["products", "electronics", "laptop-pro"], { price: 1299 });
await kv.set(["products", "electronics", "tablet-air"], { price: 799 });
await kv.set(["products", "clothing", "shirt-blue"], { price: 49 });

// List all entries under ["products", "electronics"]
const iter = kv.list<{ price: number }>({
  prefix: ["products", "electronics"],
});

for await (const entry of iter) {
  console.log(entry.key, entry.value.price);
}
// ["products", "electronics", "laptop-pro"] 1299
// ["products", "electronics", "tablet-air"] 799

// List with pagination: get 10 items at a time
const page1 = kv.list({ prefix: ["products"] }, { limit: 10 });
const results: Deno.KvEntry<unknown>[] = [];
for await (const entry of page1) {
  results.push(entry);
}

// List in reverse order (newest first in time-based keys)
const reversed = kv.list({ prefix: ["events"] }, { reverse: true, limit: 20 });

// List a specific range (useful with timestamp-based keys)
const from = new Date("2026-01-01").getTime();
const to = new Date("2026-06-30").getTime();
const rangeIter = kv.list({ start: ["events", from], end: ["events", to] });
```

---

## ACID Transactions with `atomic()`

Deno KV provides true ACID transactions — multiple read-modify-write operations either all succeed or all fail, with no partial updates visible to other readers.

```typescript
const kv = await Deno.openKv();

// Example: Transfer credits between two user accounts
async function transferCredits(
  fromUserId: string,
  toUserId: string,
  amount: number,
): Promise<boolean> {
  const fromKey = ["users", fromUserId, "credits"];
  const toKey = ["users", toUserId, "credits"];

  // Read both values first to get their versionstamps
  const [fromEntry, toEntry] = await kv.getMany<[number, number]>([fromKey, toKey]);

  if (fromEntry.value === null || toEntry.value === null) {
    throw new Error("One or both users not found");
  }

  if (fromEntry.value < amount) {
    throw new Error(`Insufficient credits: has ${fromEntry.value}, needs ${amount}`);
  }

  // Atomic transaction:
  // - check() ensures neither value changed since we read it
  // - set() writes new values
  // If any check fails (concurrent update), the entire operation is rolled back
  const result = await kv.atomic()
    .check(fromEntry)   // Abort if fromEntry has been modified
    .check(toEntry)     // Abort if toEntry has been modified
    .set(fromKey, fromEntry.value - amount)
    .set(toKey, toEntry.value + amount)
    .commit();

  if (!result.ok) {
    // Another transaction modified these keys between our read and write
    // Retry with exponential backoff or return false for the caller to retry
    return false;
  }

  return true;
}
```

The `check()` operation compares the versionstamp — if the value was written by anyone else after you read it, `commit()` returns `{ ok: false }` instead of `{ ok: true, versionstamp: "..." }`. This is **optimistic concurrency control**: no locks, no deadlocks.

---

## Key Expiration (TTL)

```typescript
const kv = await Deno.openKv();

// Set a value that expires in 1 hour
await kv.set(
  ["sessions", sessionId],
  { userId: "alice", createdAt: Date.now() },
  { expireIn: 60 * 60 * 1000 },  // milliseconds
);

// Set a value that expires in 24 hours
await kv.set(
  ["cache", "product-list"],
  products,
  { expireIn: 24 * 60 * 60 * 1000 },
);

// After expiry, get() returns { value: null }
const session = await kv.get(["sessions", sessionId]);
if (session.value === null) {
  // Session has expired or never existed
}
```

TTL is perfect for: session storage, rate limit counters, temporary tokens, cache entries.

---

## Using Versionstamps for Optimistic Locking

```typescript
const kv = await Deno.openKv();

async function updateUserEmail(userId: string, newEmail: string): Promise<void> {
  const key = ["users", userId];

  // Retry loop for optimistic concurrency
  for (let attempt = 0; attempt < 5; attempt++) {
    const entry = await kv.get<{ name: string; email: string }>(key);

    if (entry.value === null) {
      throw new Error(`User ${userId} not found`);
    }

    const updated = { ...entry.value, email: newEmail };

    const result = await kv.atomic()
      .check(entry)           // Only update if nobody else has changed this user
      .set(key, updated)
      .commit();

    if (result.ok) {
      return;  // Success
    }

    // Concurrent write detected — wait briefly and retry
    await new Promise((resolve) => setTimeout(resolve, 10 * Math.random()));
  }

  throw new Error("Failed to update after 5 attempts due to concurrent modifications");
}
```

---

## KV Watches — Real-Time Change Notifications

`kv.watch()` returns an async iterator that yields whenever the watched keys change. This is how you build real-time features without polling.

```typescript
const kv = await Deno.openKv();

// Watch a single key for changes
async function watchUserStatus(userId: string): Promise<void> {
  const stream = kv.watch<[{ status: string }]>([["users", userId, "status"]]);

  for await (const [statusEntry] of stream) {
    if (statusEntry.value === null) {
      console.log(`User ${userId} deleted`);
      break;
    }
    console.log(`User ${userId} is now: ${statusEntry.value.status}`);
  }
}

// Watch multiple keys simultaneously
const stream = kv.watch([
  ["config", "maintenance_mode"],
  ["config", "feature_flags"],
]);

for await (const [maintenanceEntry, flagsEntry] of stream) {
  if (maintenanceEntry.value === true) {
    console.log("Maintenance mode enabled — pausing job processing");
  }
}
```

---

## Complete Example: Session Management System

```typescript
// session-store.ts
const kv = await Deno.openKv();

interface Session {
  userId: string;
  email: string;
  role: "user" | "admin";
  createdAt: number;
  lastAccessedAt: number;
}

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;  // 24 hours

export async function createSession(userId: string, email: string, role: Session["role"]): Promise<string> {
  const sessionId = crypto.randomUUID();
  const now = Date.now();

  await kv.set(
    ["sessions", sessionId],
    { userId, email, role, createdAt: now, lastAccessedAt: now },
    { expireIn: SESSION_TTL_MS },
  );

  // Also track which sessions belong to this user
  await kv.set(
    ["user_sessions", userId, sessionId],
    true,
    { expireIn: SESSION_TTL_MS },
  );

  return sessionId;
}

export async function getSession(sessionId: string): Promise<Session | null> {
  const entry = await kv.get<Session>(["sessions", sessionId]);
  if (entry.value === null) return null;

  // Refresh TTL on access (sliding expiration)
  await kv.set(
    ["sessions", sessionId],
    { ...entry.value, lastAccessedAt: Date.now() },
    { expireIn: SESSION_TTL_MS },
  );

  return entry.value;
}

export async function revokeSession(sessionId: string): Promise<void> {
  const session = await kv.get<Session>(["sessions", sessionId]);
  if (session.value === null) return;

  await kv.atomic()
    .delete(["sessions", sessionId])
    .delete(["user_sessions", session.value.userId, sessionId])
    .commit();
}

export async function revokeAllUserSessions(userId: string): Promise<number> {
  const sessionKeys = kv.list({ prefix: ["user_sessions", userId] });
  let count = 0;

  for await (const entry of sessionKeys) {
    const sessionId = entry.key[2] as string;
    await kv.atomic()
      .delete(["sessions", sessionId])
      .delete(entry.key)
      .commit();
    count++;
  }

  return count;
}
```

---

## Troubleshooting

### `TypeError: Deno.openKv is not a function`

Deno KV requires `--unstable-kv` in Deno 1.x. In Deno 2, it is stable and available without flags. Upgrade to Deno 2: `deno upgrade`.

### `atomic().commit()` always returns `{ ok: false }`

The versionstamp check is failing due to a concurrent write. Implement a retry loop as shown in the `updateUserEmail` example. If running tests, ensure tests do not share KV state — use separate key namespaces per test.

### KV data not persisting between runs

If you opened with `Deno.openKv(":memory:")`, data is lost when the process exits. For persistence, use `Deno.openKv()` (default path) or `Deno.openKv("./data.db")` (explicit path).
