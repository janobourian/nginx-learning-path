# Module 07: Enterprise GraphQL — Schemas, Resolvers & The DataLoader N+1 Solution

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Graph APIs, Schema Design & DataLoader Batching

---

## 1. The GraphQL Architecture

Unlike REST (where endpoints return fixed JSON shapes), **GraphQL** allows clients to request exactly what they need across interconnected entity graphs in a single HTTP request:

```graphql

# Client Request
query GetUserProfile {
  user(id: "u_101") {
    name
    email
    orders(limit: 2) {
      id
      total
      status
    }
  }
}
```

---

## 2. Schema Definition & Resolvers

```javascript
// src/graphql/schema.js
export const typeDefs = `#graphql
  type User {
    id: ID!
    name: String!
    email: String!
    orders: [Order!]!
  }

  type Order {
    id: ID!
    total: Float!
    status: String!
    userId: ID!
  }

  type Query {
    user(id: ID!): User
    users: [User!]!
  }

  type Mutation {
    createUser(name: String!, email: String!): User!
  }
`;
```

---

## 3. The N+1 Problem in GraphQL

Consider a query fetching 50 users and their associated orders:

```javascript
// ❌ NAIVE RESOLVER (The N+1 Disaster!):
const resolvers = {
  Query: {
    users: () => db.query('SELECT * FROM users LIMIT 50'), // 1 Query
  },
  User: {
    // 💥 This resolver runs 50 separate times! (50 extra queries!)
    orders: (user) => db.query('SELECT * FROM orders WHERE user_id = $1', [user.id]),
  },
};
```

For 50 users, this executes **51 separate database queries (1 + N)**, saturating the database and spiking latency.

---

## 4. The DataLoader Solution (Batching & Memoization)

**DataLoader** (created by Facebook) solves the N+1 problem by **batching all individual keys requested within a single Event Loop tick into one single array**:

```text
DataLoader Batching Cycle:
50 User resolvers call userOrdersLoader.load(userId) within the SAME tick
       │
       ▼ (Batched automatically into a single array: [id1, id2, ... id50])
[Single SQL Query]: "SELECT * FROM orders WHERE user_id IN ($1, $2, ... $50)"
       │
       ▼
DataLoader maps results back to each user promise! (Total Queries: EXACTLY 2!)
```

### Implementing DataLoader with PostgreSQL

```javascript
// src/graphql/loaders/order_loader.js
import DataLoader from 'dataloader';
import { dbPool } from '../../database/postgres_pool.js';

export function createOrderLoader() {
  return new DataLoader(async (userIds) => {
    console.log(`[DataLoader]: Batching SQL query for ${userIds.length} users...`);

    // 1. Single batched query using ANY() / IN():
    const query = `
      SELECT id, total, status, user_id
      FROM orders
      WHERE user_id = ANY($1);
    `;

    const { rows } = await dbPool.query(query, [userIds]);

    // 2. Group orders by userId:
    const ordersByUser = new Map();
    userIds.forEach((id) => ordersByUser.set(id, []));

    for (const order of rows) {
      ordersByUser.get(order.user_id)?.push(order);
    }

    // 3. Return array matching the exact order of incoming userIds:
    return userIds.map((id) => ordersByUser.get(id) || []);
  });
}
```

### Resolver Integration via GraphQL Context

```javascript
// src/graphql/resolvers.js
export const resolvers = {
  Query: {
    users: async (_, __, { db }) => {
      const { rows } = await db.query('SELECT * FROM users LIMIT 50');
      return rows;
    },
  },
  User: {
    // Zero N+1 queries! Batched seamlessly via DataLoader:
    orders: (user, _, { loaders }) => {
      return loaders.orderLoader.load(user.id);
    },
  },
};
```

---

## 5. Security & DOS Protection: Query Depth Limiting

Malicious clients can submit recursive circular queries (e.g. `user { orders { user { orders { user { ... } } } } }`) that exhaust server memory.

Use **`graphql-depth-limit`** to enforce a maximum nesting depth:

```javascript
import depthLimit from 'graphql-depth-limit';
import { createYoga } from 'graphql-yoga';

export const yoga = createYoga({
  schema,
  validationRules: [
    depthLimit(5), // Reject queries nested deeper than 5 levels!
  ],
});
```

---

## Troubleshooting & Best Practices

1. **Instantiate DataLoaders Per-Request in Context**
   Never create a single global `DataLoader` singleton across all requests. DataLoaders cache results in memory; sharing a DataLoader globally will leak private user data across different HTTP requests! Always instantiate fresh loaders inside the request context.

2. **Disable Introspection in Production**
   Disable GraphQL schema introspection on public production servers to prevent attackers from mapping your internal schema data model.
