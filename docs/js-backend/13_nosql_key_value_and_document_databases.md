# Module 13: NoSQL Document & Wide-Column Databases — MongoDB & DynamoDB

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** NoSQL Systems, Document Stores & Distributed Partitioning

---

## 1. NoSQL Architectural Paradigms

```text
┌─────────────────────────────────────────────────────────────┐
│                 NoSQL Database Classification               │
├────────────────────┬────────────────────────────────────────┤
│ **1. Document**    │ **MongoDB**                            │
│    **Stores**      │ - Nested BSON documents with rich      │
│                    │   sub-arrays and aggregation pipelines.│
├────────────────────┼────────────────────────────────────────┤
│ **2. Wide-Column** │ **DynamoDB / Cassandra**               │
│    **Stores**      │ - Extreme horizontal scale with fixed  │
│                    │   Partition Keys (PK) & Sort Keys (SK).│
├────────────────────┼────────────────────────────────────────┤
│ **3. Key-Value**   │ **Redis / Deno KV / RocksDB**          │
│                    │ - Sub-millisecond in-memory lookups.   │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. MongoDB High-Performance Query Optimization

### Indexing Strategies & `explain('executionStats')`

Without compound indexes, MongoDB executes full collection scans (`COLLSCAN`), consuming 100% CPU.

```javascript
// src/database/mongo_indices.js
export async function createEnterpriseIndices(db) {
  const collection = db.collection('orders');

  // Compound Index for fast user filtering & chronological sorting:
  await collection.createIndex(
    { userId: 1, createdAt: -1 },
    { background: true, name: 'idx_user_orders_date' }
  );

  // Partial Index for active pending orders only (Saves 80% index RAM!):
  await collection.createIndex(
    { orderId: 1 },
    {
      partialFilterExpression: { status: 'PENDING' },
      name: 'idx_pending_orders',
    }
  );
}
```

---

## 3. Single-Table Design with DynamoDB (`@aws-sdk/client-dynamodb`)

In **Amazon DynamoDB**, instead of creating 10 separate tables, enterprise systems use **Single-Table Design**: all entities (Users, Orders, Products) are stored in a single table partitioned by composite keys:

```text
┌─────────────────────────────────────────────────────────────┐
│                 DynamoDB Single-Table Schema                │
├──────────────────────┬──────────────────────┬───────────────┤
│ **Partition Key (PK)**│ **Sort Key (SK)**   │ **Data**      │
├──────────────────────┼──────────────────────┼───────────────┤
│ `USER#u_101`         │ `METADATA`           │ Profile info  │
│ `USER#u_101`         │ `ORDER#2026-001`     │ Order payload │
│ `PRODUCT#p_500`      │ `METADATA`           │ Price & Stock │
└──────────────────────┴──────────────────────┴───────────────┘
```

### Conditional Writes (Race Condition Protection)

```javascript
// src/database/dynamodb_service.js
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

export async function placeOrderAtomic(orderId, userId, amount) {
  const command = new PutCommand({
    TableName: 'EnterpriseAppTable',
    Item: {
      PK: `USER#${userId}`,
      SK: `ORDER#${orderId}`,
      amount,
      status: 'CONFIRMED',
      createdAt: new Date().toISOString(),
    },
    // Prevent overwriting existing order with same ID:
    ConditionExpression: 'attribute_not_exists(PK) AND attribute_not_exists(SK)',
  });

  try {
    await docClient.send(command);
    console.log('Order placed atomically in DynamoDB!');
  } catch (err) {
    if (err.name === 'ConditionalCheckFailedException') {
      throw new Error('Order with this ID already exists!');
    }
    throw err;
  }
}
```

---

## Troubleshooting & Best Practices

1. **Avoid the Unbounded Array Anti-Pattern in MongoDB**
   Never push infinite items into a single document array (e.g. `user.activityLog.push(event)`). MongoDB has a strict **16MB BSON document limit**. Store activity logs as separate documents referenced by `userId`.

2. **Always Use Projection Queries**
   In MongoDB and DynamoDB, fetching entire documents when only two fields are needed wastes network bandwidth and database memory. Always pass explicit projection filters (`{ projection: { name: 1, email: 1 } }`).
