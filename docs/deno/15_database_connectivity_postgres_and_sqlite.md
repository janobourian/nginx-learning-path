# Module 15: Database Connectivity — PostgreSQL & SQLite

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Persistence & Data Access

---

## Database Options in Deno

Deno applications have several database connectivity options:

- **`postgres` (JSR: `@db/postgres`)** — Native PostgreSQL driver written for Deno
- **`npm:pg`** — The classic Node.js PostgreSQL driver via npm compatibility
- **Deno KV** — Built-in key-value store (covered in Module 04)
- **SQLite via `@db/sqlite`** — Embedded SQLite using Deno FFI
- **`npm:better-sqlite3`** — Node.js SQLite driver via npm compat

For production applications, PostgreSQL is the standard relational choice. SQLite is ideal for local development, embedded tools, and single-server deployments.

---

## PostgreSQL with `@db/postgres`

```json
{
  "imports": {
    "@db/postgres": "jsr:@db/postgres@^0.17"
  }
}
```

### Basic Connection and Queries

```typescript
import { Client } from "@db/postgres";

// Single client connection
const client = new Client({
  hostname: Deno.env.get("PGHOST") ?? "localhost",
  port: Number(Deno.env.get("PGPORT") ?? "5432"),
  database: Deno.env.get("PGDATABASE") ?? "myapp",
  user: Deno.env.get("PGUSER") ?? "postgres",
  password: Deno.env.get("PGPASSWORD"),
  tls: {
    enabled: Deno.env.get("PGSSLMODE") === "require",
    enforce: Deno.env.get("PGSSLMODE") === "require",
  },
});

await client.connect();

try {
  // Simple query — no parameters
  const result = await client.queryObject<{ version: string }>(
    "SELECT version()"
  );
  console.log("PostgreSQL:", result.rows[0].version);

  // Parameterized query — always use parameters for user input!
  const userId = "user_123";
  const users = await client.queryObject<{ id: string; name: string; email: string }>(
    "SELECT id, name, email FROM users WHERE id = $1 AND active = true",
    [userId],
  );

  if (users.rows.length === 0) {
    console.log("User not found");
  } else {
    console.log(users.rows[0]);
  }

  // Insert with RETURNING
  const newUser = await client.queryObject<{ id: string; created_at: Date }>(
    `INSERT INTO users (id, name, email, password_hash, created_at)
     VALUES ($1, $2, $3, $4, NOW())
     RETURNING id, created_at`,
    [crypto.randomUUID(), "Alice", "alice@example.com", "hashed_password"],
  );
  console.log("Created user:", newUser.rows[0]);

} finally {
  await client.end();
}
```

### Connection Pool

For production servers handling concurrent requests, always use a connection pool:

```typescript
import { Pool } from "@db/postgres";

// Create a pool with a maximum of 20 connections
const pool = new Pool({
  hostname: Deno.env.get("PGHOST") ?? "localhost",
  port: 5432,
  database: Deno.env.get("PGDATABASE") ?? "myapp",
  user: Deno.env.get("PGUSER") ?? "postgres",
  password: Deno.env.get("PGPASSWORD"),
}, 20);  // max connections

// Helper function to run a query using a pooled connection
async function query<T>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const client = await pool.connect();
  try {
    const result = await client.queryObject<T>(sql, params);
    return result.rows;
  } finally {
    client.release();  // Return connection to pool — critical!
  }
}

// Usage
const users = await query<{ id: string; name: string }>(
  "SELECT id, name FROM users WHERE active = true ORDER BY name"
);
```

### Transactions

```typescript
async function transferFunds(
  fromAccount: string,
  toAccount: string,
  amount: number,
): Promise<void> {
  const client = await pool.connect();

  try {
    await client.queryObject("BEGIN");

    // Check balance
    const balance = await client.queryObject<{ balance: number }>(
      "SELECT balance FROM accounts WHERE id = $1 FOR UPDATE",
      [fromAccount],
    );

    if (!balance.rows[0] || balance.rows[0].balance < amount) {
      throw new Error("Insufficient funds");
    }

    // Debit
    await client.queryObject(
      "UPDATE accounts SET balance = balance - $1, updated_at = NOW() WHERE id = $2",
      [amount, fromAccount],
    );

    // Credit
    await client.queryObject(
      "UPDATE accounts SET balance = balance + $1, updated_at = NOW() WHERE id = $2",
      [amount, toAccount],
    );

    // Record transaction
    await client.queryObject(
      `INSERT INTO transactions (id, from_account, to_account, amount, created_at)
       VALUES ($1, $2, $3, $4, NOW())`,
      [crypto.randomUUID(), fromAccount, toAccount, amount],
    );

    await client.queryObject("COMMIT");
  } catch (error) {
    await client.queryObject("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
```

---

## PostgreSQL Schema Management

```typescript
// migrations/001_initial_schema.sql pattern
// Run migrations programmatically

const MIGRATIONS = [
  {
    version: 1,
    name: "initial_schema",
    up: `
      CREATE TABLE IF NOT EXISTS users (
        id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email       TEXT NOT NULL UNIQUE,
        name        TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role        TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin', 'moderator')),
        active      BOOLEAN NOT NULL DEFAULT true,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
      CREATE INDEX IF NOT EXISTS idx_users_active ON users(active) WHERE active = true;

      CREATE TABLE IF NOT EXISTS sessions (
        id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token_hash  TEXT NOT NULL UNIQUE,
        expires_at  TIMESTAMPTZ NOT NULL,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token_hash);
      CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
    `,
  },
];

async function runMigrations(): Promise<void> {
  const client = await pool.connect();
  try {
    // Create migrations table if it doesn't exist
    await client.queryObject(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    // Find applied migrations
    const applied = await client.queryObject<{ version: number }>(
      "SELECT version FROM schema_migrations ORDER BY version"
    );
    const appliedVersions = new Set(applied.rows.map((r) => r.version));

    // Apply pending migrations
    for (const migration of MIGRATIONS) {
      if (appliedVersions.has(migration.version)) continue;

      console.log(`Applying migration ${migration.version}: ${migration.name}`);
      await client.queryObject("BEGIN");
      try {
        await client.queryObject(migration.up);
        await client.queryObject(
          "INSERT INTO schema_migrations (version, name) VALUES ($1, $2)",
          [migration.version, migration.name],
        );
        await client.queryObject("COMMIT");
        console.log(`Migration ${migration.version} applied successfully`);
      } catch (err) {
        await client.queryObject("ROLLBACK");
        throw new Error(`Migration ${migration.version} failed: ${err}`);
      }
    }
  } finally {
    client.release();
  }
}
```

---

## SQLite with `@db/sqlite`

```json
{
  "imports": {
    "@db/sqlite": "jsr:@db/sqlite@^0.12"
  }
}
```

```typescript
import { Database } from "@db/sqlite";

// Open SQLite database (creates if not exists)
const db = new Database("./local.db");

// Enable WAL mode for better concurrent read performance
db.exec("PRAGMA journal_mode = WAL");
db.exec("PRAGMA foreign_keys = ON");

// Create schema
db.exec(`
  CREATE TABLE IF NOT EXISTS tasks (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    done       INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

// Insert with prepared statement (efficient for repeated inserts)
const insertTask = db.prepare(
  "INSERT INTO tasks (id, title, done) VALUES (?, ?, ?)"
);
insertTask.run(crypto.randomUUID(), "Buy groceries", 0);
insertTask.run(crypto.randomUUID(), "Write tests", 0);
insertTask.run(crypto.randomUUID(), "Deploy to production", 1);

// Query with typed results
const tasks = db.prepare("SELECT id, title, done FROM tasks WHERE done = ?")
  .all<{ id: string; title: string; done: number }>(0);

for (const task of tasks) {
  console.log(`☐ ${task.title} (${task.id})`);
}

// Transaction
const transferTransaction = db.transaction((from: string, to: string, amount: number) => {
  const fromBalance = db.prepare("SELECT balance FROM accounts WHERE id = ?")
    .get<{ balance: number }>(from);

  if (!fromBalance || fromBalance.balance < amount) {
    throw new Error("Insufficient balance");
  }

  db.prepare("UPDATE accounts SET balance = balance - ? WHERE id = ?").run(amount, from);
  db.prepare("UPDATE accounts SET balance = balance + ? WHERE id = ?").run(amount, to);
});

transferTransaction("acc_1", "acc_2", 50);

db.close();
```

---

## Repository Pattern for Database Access

```typescript
// repositories/user_repository.ts
import { Pool } from "@db/postgres";

interface User {
  id: string;
  email: string;
  name: string;
  role: "user" | "admin";
  active: boolean;
  createdAt: Date;
}

interface CreateUserInput {
  email: string;
  name: string;
  passwordHash: string;
}

export class UserRepository {
  constructor(private readonly pool: Pool) {}

  async findById(id: string): Promise<User | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.queryObject<{
        id: string; email: string; name: string;
        role: string; active: boolean; created_at: Date;
      }>(
        "SELECT id, email, name, role, active, created_at FROM users WHERE id = $1",
        [id],
      );
      if (result.rows.length === 0) return null;
      return this.mapRow(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async findByEmail(email: string): Promise<User | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.queryObject<{
        id: string; email: string; name: string;
        role: string; active: boolean; created_at: Date;
      }>(
        "SELECT id, email, name, role, active, created_at FROM users WHERE email = $1",
        [email.toLowerCase()],
      );
      return result.rows[0] ? this.mapRow(result.rows[0]) : null;
    } finally {
      client.release();
    }
  }

  async create(input: CreateUserInput): Promise<User> {
    const client = await this.pool.connect();
    try {
      const result = await client.queryObject<{
        id: string; email: string; name: string;
        role: string; active: boolean; created_at: Date;
      }>(
        `INSERT INTO users (id, email, name, password_hash)
         VALUES ($1, $2, $3, $4)
         RETURNING id, email, name, role, active, created_at`,
        [crypto.randomUUID(), input.email.toLowerCase(), input.name, input.passwordHash],
      );
      return this.mapRow(result.rows[0]);
    } finally {
      client.release();
    }
  }

  private mapRow(row: {
    id: string; email: string; name: string;
    role: string; active: boolean; created_at: Date;
  }): User {
    return {
      id: row.id,
      email: row.email,
      name: row.name,
      role: row.role as "user" | "admin",
      active: row.active,
      createdAt: row.created_at,
    };
  }
}
```

---

## Troubleshooting

### `Error: Connection refused — is the database running?`

Verify PostgreSQL is running: `pg_isready -h localhost -p 5432`. Check that the hostname, port, database name, and credentials in your connection config match. For Docker-based PostgreSQL: ensure the container is started and the port is mapped.

### Pool connection exhausted — queries time out

Increase the pool size or add a query timeout. All 20 connections are in use simultaneously, likely indicating slow queries or connection leaks (forgetting `client.release()`). Always use try/finally to ensure release.

### SQLite `SQLITE_BUSY` error under concurrent writes

SQLite only allows one writer at a time. Enable WAL mode (`PRAGMA journal_mode = WAL`) which allows concurrent reads alongside one write. If you have high write concurrency, switch to PostgreSQL.
