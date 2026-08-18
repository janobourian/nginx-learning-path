# Module 12: Relational Databases — Connection Pooling, ACID Transactions & Isolation Levels

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Database Engineering, PostgreSQL & Transaction Isolation

---

## 1. Connection Pool Architecture & Tuning

Opening a TCP connection to PostgreSQL incurs TLS handshakes, authentication checks, and backend process spawning (~40ms latency).

A **Connection Pool** maintains pre-warmed connections ready for immediate reuse:

```
┌─────────────────────────────────────────────────────────────┐
│                 PostgreSQL Connection Pool Sizing           │
├─────────────────────────────────────────────────────────────┤
│ **The PostgreSQL Pool Formula:**                            │
│ `pool_size = (core_count * 2) + effective_spindle_count`    │
│ - For a 4-Core Database with NVMe SSD:                      │
│   Optimal Pool = (4 * 2) + 1 = **9 to 15 Connections**!     │
│ - Allocating 500 connections degrades performance due to    │
│   OS process context-switching overhead!                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Preventing Race Conditions with Row-Level Locking (`FOR UPDATE`)

In e-commerce inventory or financial balance updates, two concurrent requests can read the same balance simultaneously, resulting in a **Double-Spending Bug**:

```sql
-- Request 1 and Request 2 both read balance = $100 simultaneously:
-- Request 1 deducts $80 and writes balance = $20
-- Request 2 deducts $80 and writes balance = $20 (User spent $160 with only $100!)
```

### The Solution: Row-Level Locking (`SELECT ... FOR UPDATE`)

```javascript
// src/services/wallet_service.js
import { dbPool } from '../database/postgres_pool.js';

export async function transferFunds(fromUserId, toUserId, amount) {
  const client = await dbPool.connect();

  try {
    await client.query('BEGIN');

    // 1. Lock sender row with 'FOR UPDATE' (Blocks concurrent transactions until commit):
    const senderRes = await client.query(
      'SELECT id, balance FROM accounts WHERE user_id = $1 FOR UPDATE',
      [fromUserId]
    );

    if (senderRes.rowCount === 0) throw new Error('Sender account not found');
    const senderBalance = Number(senderRes.rows[0].balance);

    if (senderBalance < amount) {
      throw new Error(`Insufficient funds: Balance is \$${senderBalance}`);
    }

    // 2. Lock receiver row:
    await client.query(
      'SELECT id FROM accounts WHERE user_id = $1 FOR UPDATE',
      [toUserId]
    );

    // 3. Execute balance updates:
    await client.query(
      'UPDATE accounts SET balance = balance - $1 WHERE user_id = $2',
      [amount, fromUserId]
    );

    await client.query(
      'UPDATE accounts SET balance = balance + $1 WHERE user_id = $2',
      [amount, toUserId]
    );

    // 4. Commit ACID transaction:
    await client.query('COMMIT');
    return { success: true, transferred: amount };
  } catch (err) {
    // 5. Rollback on failure:
    await client.query('ROLLBACK');
    throw err;
  } finally {
    // 6. Release connection back to pool:
    client.release();
  }
}
```

---

## 3. ACID Transaction Isolation Levels

| Isolation Level | Dirty Reads | Non-Repeatable Reads | Phantom Reads | Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **`READ COMMITTED`** (Postgres Default) | Prevented | Possible | Possible | 90% of standard CRUD queries |
| **`REPEATABLE READ`** | Prevented | **Prevented** | Prevented in Postgres | Consistent reporting and analytics exports |
| **`SERIALIZABLE`** | Prevented | **Prevented** | **Prevented** | Financial ledgers (Retries needed on serialization failures) |

```javascript
// Setting custom isolation level:
await client.query('BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE');
```

---

## 4. Zero-Downtime Database Migration Best Practices

When deploying schema changes in high-traffic applications:
1. **Never rename columns directly** (Breaks active microservices running old code).
2. **The Expand/Contract Pattern**:
   - **Expand**: Add new column `full_name`.
   - **Dual-Write**: Update application code to write to both `name` and `full_name`.
   - **Backfill**: Migrate historical records in small batches.
   - **Contract**: Remove writes to old `name` column and drop column.

---

## Troubleshooting & Best Practices

1. **Deadlock Prevention in Multi-Row Updates**
   When updating multiple rows in a transaction (e.g. transfer between Account A and Account B), **always lock rows in a consistent sorted order** (e.g. `ORDER BY user_id ASC`). Inconsistent lock acquisition orders trigger database transaction deadlocks.

2. **Set `statement_timeout`**
   Configure `statement_timeout = '5s'` on database pools to automatically abort runaway slow queries before they exhaust server connection slots.
