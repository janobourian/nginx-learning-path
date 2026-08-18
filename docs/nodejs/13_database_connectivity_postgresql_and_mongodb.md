# Module 13: Enterprise Database Connectivity — PostgreSQL & MongoDB

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Data Persistence, Connection Pooling & ACID Transactions

---

## 1. Relational Engineering with PostgreSQL (`pg.Pool`)

In production, creating a new TCP connection to PostgreSQL on every HTTP request takes ~50ms and exhausts database process handles.

Always use a **Connection Pool (`pg.Pool`)**:

```bash
npm install pg dotenv
```

```javascript
// src/database/postgres_pool.js
import pg from 'pg';

const { Pool } = pg;

export const dbPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,                  // Max concurrent connections in pool
  idleTimeoutMillis: 30000, // Close idle connections after 30s
  connectionTimeoutMillis: 2000, // Fail fast if pool is saturated
});

dbPool.on('error', (err) => {
  console.error('[PostgreSQL Pool Error]: Unexpected idle client error', err);
});
```

---

## 2. Preventing SQL Injection with Parameterized Queries

Never concatenate variables into SQL strings (`'SELECT * FROM users WHERE id = ' + id`). Always use **Parameterized Placeholders (`$1, $2`)**:

```javascript
// src/repositories/user_repository.js
import { dbPool } from '../database/postgres_pool.js';

export async function findUserByEmail(email) {
  const query = `
    SELECT id, email, full_name, role, created_at
    FROM users
    WHERE email = $1
    LIMIT 1;
  `;

  // $1 is safely escaped by the database engine driver:
  const result = await dbPool.query(query, [email]);
  return result.rows[0] || null;
}
```

---

## 3. ACID Transactions with Manual Client Checkout

When executing multi-table mutations (e.g. creating an order and deducting account balance), wrap operations in an explicit **ACID Transaction (`BEGIN / COMMIT / ROLLBACK`)**:

```javascript
// src/services/checkout_service.js
import { dbPool } from '../database/postgres_pool.js';

export async function processOrderTransaction(userId, totalAmount, cartItems) {
  // 1. Checkout a dedicated client from pool:
  const client = await dbPool.connect();

  try {
    // 2. Begin ACID Transaction:
    await client.query('BEGIN');

    // 3. Deduct balance with row-level lock (FOR UPDATE):
    const balanceRes = await client.query(
      'UPDATE accounts SET balance = balance - $1 WHERE user_id = $2 AND balance >= $1 RETURNING balance',
      [totalAmount, userId]
    );

    if (balanceRes.rowCount === 0) {
      throw new Error('Insufficient funds or account not found');
    }

    // 4. Create Order:
    const orderRes = await client.query(
      'INSERT INTO orders (user_id, total, status) VALUES ($1, $2, $3) RETURNING id',
      [userId, totalAmount, 'CONFIRMED']
    );
    const orderId = orderRes.rows[0].id;

    // 5. Insert Line Items:
    for (const item of cartItems) {
      await client.query(
        'INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES ($1, $2, $3, $4)',
        [orderId, item.productId, item.quantity, item.price]
      );
    }

    // 6. Commit Transaction to disk:
    await client.query('COMMIT');
    return { success: true, orderId };
  } catch (err) {
    // 7. Rollback all mutations if ANY step fails!
    await client.query('ROLLBACK');
    throw err;
  } finally {
    // 8. CRITICAL: Always release client back to pool!
    client.release();
  }
}
```

---

## 4. NoSQL Document Persistence with MongoDB Native Driver

```bash
npm install mongodb
```

```javascript
// src/database/mongo_client.js
import { MongoClient, ServerApiVersion } from 'mongodb';

const uri = process.env.MONGODB_URI;

export const mongoClient = new MongoClient(uri, {
  serverApi: {
    version: ServerApiVersion.v1,
    strict: true,
    deprecationErrors: true,
  },
  maxPoolSize: 50,
  minPoolSize: 10,
  writeConcern: { w: 'majority', j: true }, // ACID-like durability across replica set!
});

export async function connectMongo() {
  await mongoClient.connect();
  console.log('Connected to MongoDB Replica Set with connection pooling.');
  return mongoClient.db('enterprise_db');
}
```

---

## 5. High-Performance Aggregation Pipelines in MongoDB

```javascript
// src/repositories/analytics_repository.js
import { mongoClient } from '../database/mongo_client.js';

export async function calculateMonthlyRevenueByRegion() {
  const db = mongoClient.db('enterprise_db');
  const collection = db.collection('orders');

  // Aggregation Pipeline executing directly in MongoDB engine:
  const pipeline = [
    { $match: { status: 'COMPLETED' } },
    {
      $group: {
        _id: '$region',
        totalRevenue: { $sum: '$totalAmount' },
        orderCount: { $sum: 1 },
        averageTicket: { $avg: '$totalAmount' },
      },
    },
    { $sort: { totalRevenue: -1 } },
    {
      $project: {
        _id: 0,
        region: '$_id',
        totalRevenue: { $round: ['$totalRevenue', 2] },
        orderCount: 1,
      },
    },
  ];

  return await collection.aggregate(pipeline).toArray();
}
```

---

## Troubleshooting & Best Practices

1. **Always Wrap Client Checkout in `try ... finally { client.release(); }`**
   If you forget `client.release()`, the checked-out PostgreSQL connection is never returned to the pool. After 20 requests, the entire pool is exhausted and all subsequent HTTP requests will hang indefinitely!

2. **Always Index Foreign Keys and Query Predicates**
   Run `EXPLAIN ANALYZE SELECT ...` in PostgreSQL. Queries without indexes trigger full sequential table scans that lock CPU cores.
