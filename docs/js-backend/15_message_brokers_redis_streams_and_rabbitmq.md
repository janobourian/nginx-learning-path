# Module 15: Message Brokers — RabbitMQ (AMQP), Redis Streams & Dead Letter Queues

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Event-Driven Architecture, AMQP & Distributed Message Queues

---

## 1. Message Broker Comparison Matrix

```text
┌─────────────────────────────────────────────────────────────┐
│                 Message Broker Feature Matrix               │
├───────────────────┬──────────────────┬──────────────────────┤
│ Feature           │ RabbitMQ (AMQP)  │ Redis Streams        │ Apache Kafka         │
├───────────────────┼──────────────────┼──────────────────────┤
│ **Architecture**  │ **Smart Broker,  │ In-Memory Log with   │ **Distributed Partition│
│                   │ Dumb Consumer**  │ Consumer Groups      │ Log**                │
│ **Routing Engine**│ **Exchanges      │ Stream Keys          │ Topic Partitions     │
│                   │ (Topic, Direct)**│                      │                      │
│ **Throughput**    │ ~50k msg/sec     │ ~200k msg/sec        │ **1M+ msg/sec**      │
│ **Persistence**   │ Disk & Memory    │ In-Memory + AOF/RDB  │ Append-Only Disk Log │
│ **Best For**      │ Complex routing, │ Lightweight micro-   │ Massive big data &   │
│                   │ tasks, RPC       │ service streaming    │ analytics pipelines  │
└───────────────────┴──────────────────┴──────────────────────┘
```

---

## 2. RabbitMQ Architecture: Exchanges, Queues & Bindings

In RabbitMQ (AMQP 0-9-1 protocol), producers **never publish messages directly to a queue**. Instead, messages are sent to an **Exchange**, which routes them to queues based on **Binding Keys**:

```text
RabbitMQ AMQP Architecture:
[Producer] ──► [Exchange (Topic: 'orders.*')]
                     │
                     ├─► (Binding: 'orders.created') ──► [Queue: OrderProcessor] ──► [Worker 1]
                     └─► (Binding: 'orders.refunded')──► [Queue: RefundService]   ──► [Worker 2]
```

---

## 3. Production RabbitMQ Consumer with Dead Letter Queue (DLQ)

```bash
npm install amqplib
```

```javascript
// src/messaging/rabbitmq_consumer.js
import amqp from 'amqplib';

export class ResilientQueueConsumer {
  constructor(amqpUrl) {
    this.amqpUrl = amqpUrl;
    this.connection = null;
    this.channel = null;
  }

  async connect() {
    this.connection = await amqp.connect(this.amqpUrl);
    this.channel = await this.connection.createChannel();

    // Limit unacknowledged messages to 10 per worker (Prefetch!):
    await this.channel.prefetch(10);

    // 1. Setup Dead Letter Exchange (DLX) for failed poisonous messages:
    await this.channel.assertExchange('dlx.exchange', 'direct', { durable: true });
    await this.channel.assertQueue('orders.dlq', { durable: true });
    await this.channel.bindQueue('orders.dlq', 'dlx.exchange', 'orders.dead');

    // 2. Setup Main Queue with DLX configuration:
    await this.channel.assertQueue('orders.process', {
      durable: true,
      arguments: {
        'x-dead-letter-exchange': 'dlx.exchange',
        'x-dead-letter-routing-key': 'orders.dead',
        'x-max-priority': 10,
      },
    });

    console.log('RabbitMQ queues & Dead Letter Exchanges asserted.');
  }

  async startListening() {
    this.channel.consume('orders.process', async (msg) => {
      if (!msg) return;

      try {
        const payload = JSON.parse(msg.content.toString());
        console.log(`[RabbitMQ]: Processing Order #${payload.orderId}...`);

        // Execute business logic:
        await this._processOrder(payload);

        // Acknowledge message upon successful completion:
        this.channel.ack(msg);
      } catch (err) {
        console.error('[RabbitMQ Error]: Failed to process message:', err.message);

        // Reject without requeueing -> Automatically routes message to DLQ!
        this.channel.reject(msg, false); // false = Do NOT requeue to main queue!
      }
    });
  }

  async _processOrder(order) {
    // Process payment & update inventory...
  }
}
```

---

## 4. Redis Streams with Consumer Groups

```javascript
// src/messaging/redis_stream_worker.js
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);
const STREAM = 'orders:stream';
const GROUP = 'order_processors';
const CONSUMER = `worker_${process.pid}`;

export async function initRedisStreamGroup() {
  try {
    // Create consumer group starting at beginning of stream:
    await redis.xgroup('CREATE', STREAM, GROUP, '0', 'MKSTREAM');
  } catch (err) {
    if (!err.message.includes('BUSYGROUP')) throw err;
  }
}

export async function processStreamLoop() {
  while (true) {
    // Read new pending messages for this consumer group:
    const response = await redis.xreadgroup(
      'GROUP', GROUP, CONSUMER,
      'BLOCK', 5000,
      'COUNT', 10,
      'STREAMS', STREAM, '>'
    );

    if (response) {
      const [streamKey, messages] = response[0];

      for (const [messageId, fields] of messages) {
        const payload = JSON.parse(fields[1]);
        console.log(`[Redis Stream]: Processing message ${messageId}`);

        // Acknowledge processed message:
        await redis.xack(STREAM, GROUP, messageId);
      }
    }
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Set `channel.prefetch(N)` in RabbitMQ**
   By default, RabbitMQ sends all queued messages to the first connected worker without waiting for acknowledgments. Setting `prefetch(10)` ensures even load balancing across all worker pods.

2. **Handle Idempotency in Consumers**
   Message brokers guarantee **At-Least-Once Delivery** (network glitches can cause duplicate message dispatches). Always record processed message IDs in Redis to prevent duplicate operations.
