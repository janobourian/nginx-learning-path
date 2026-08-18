# Module 16: Automated Testing — `node:test`, Integration Testing & Load Testing with `autocannon`

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Testing Architecture, Test Runners & Load Benchmarking

---

## 1. The Built-in Node.js Test Runner (`node:test`)

Starting with Node.js 18 LTS and stabilized in Node.js 20+, Node.js includes a blazing-fast **Native Test Runner** that eliminates the need for heavy external frameworks like Jest or Mocha:

```bash
# Run all tests in the project natively:
node --test

# Run tests with code coverage report:
node --test --experimental-test-coverage

# Watch mode for rapid TDD:
node --test --watch
```

---

## 2. Unit Testing with `node:test` & `node:assert/strict`

```javascript
// test/unit/pricing_engine.test.js
import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';

class DiscountService {
  async fetchTierDiscount(tier) {
    // Simulates remote database lookup
    return tier === 'ENTERPRISE' ? 0.20 : 0.05;
  }
}

class PricingCalculator {
  constructor(discountService) {
    this.discountService = discountService;
  }

  async calculateTotal(subtotal, tier) {
    if (subtotal < 0) {
      throw new RangeError('Subtotal must be non-negative.');
    }
    const discount = await this.discountService.fetchTierDiscount(tier);
    return Math.round(subtotal * (1 - discount) * 100) / 100;
  }
}

describe('PricingCalculator Test Suite', () => {
  let discountService;
  let calculator;

  beforeEach(() => {
    discountService = new DiscountService();
    calculator = new PricingCalculator(discountService);
  });

  it('calculates correct discounted total for ENTERPRISE tier', async () => {
    // 1. Mock method on discount service:
    const mockDiscount = mock.method(discountService, 'fetchTierDiscount', async () => 0.25);

    const total = await calculator.calculateTotal(100.0, 'ENTERPRISE');

    // 2. Strict Assertions:
    assert.equal(total, 75.0);
    assert.equal(mockDiscount.mock.calls.length, 1);
    assert.deepEqual(mockDiscount.mock.calls[0].arguments, ['ENTERPRISE']);
  });

  it('throws RangeError when negative amount is passed', async () => {
    await assert.rejects(
      async () => await calculator.calculateTotal(-50, 'STANDARD'),
      {
        name: 'RangeError',
        message: 'Subtotal must be non-negative.',
      }
    );
  });
});
```

---

## 3. Integration Testing HTTP APIs with Native `fetch`

Test your Express or Fastify microservices against live ephemeral ports:

```javascript
// test/integration/users_api.test.js
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { app } from '../../src/app.js';

describe('Users API End-to-End Integration Tests', () => {
  let server;
  let baseUrl;

  before(async () => {
    // Start server on random ephemeral OS port (port: 0):
    server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    const port = server.address().port;
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    await new Promise((resolve) => server.close(resolve));
  });

  it('POST /api/v1/users creates user and returns 201 Created', async () => {
    const payload = {
      name: 'Alice Chen',
      email: 'alice@acme.com',
      role: 'admin',
    };

    const response = await fetch(`${baseUrl}/api/v1/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    assert.equal(response.status, 201);
    const body = await response.json();

    assert.equal(body.success, true);
    assert.equal(body.data.name, 'Alice Chen');
    assert.ok(body.data.id.startsWith('u_'));
  });

  it('GET /api/v1/users/404 returns 404 Not Found error', async () => {
    const response = await fetch(`${baseUrl}/api/v1/users/404`);
    assert.equal(response.status, 404);
  });
});
```

---

## 4. Load & Stress Testing with `autocannon`

Before deploying to production, measure your API's throughput (Requests/sec) and latency percentiles (p95, p99) under high concurrent load:

```bash
npm install -g autocannon
```

### 1. Running a High-Concurrency Benchmark:

```bash
# Benchmark with 100 concurrent connections over 10 seconds:
autocannon -c 100 -d 10 -p 10 http://localhost:3000/api/v1/users/u_101
```

### 2. Programmatic Load Test in CI (`scripts/load_test.js`)

```javascript
// scripts/load_test.js
import autocannon from 'autocannon';

async function runLoadBenchmark() {
  console.log('Initiating automated API load test (100 concurrent connections)...');

  const result = await autocannon({
    url: 'http://localhost:3000/health',
    connections: 100,
    duration: 10,
    pipelining: 1,
  });

  console.log('=== Benchmark Results ===');
  console.log(`Requests/sec:   ${result.requests.average}`);
  console.log(`Latency (p50):  ${result.latency.p50} ms`);
  console.log(`Latency (p95):  ${result.latency.p95} ms`);
  console.log(`Latency (p99):  ${result.latency.p99_9} ms`);
  console.log(`2xx Responses:  ${result['2xx']}`);
  console.log(`Non-2xx Errors: ${result.non2xx}`);

  // CI Quality Gate: Fail build if p99 latency exceeds 50ms:
  if (result.latency.p99 > 50) {
    console.error('❌ Build Failed: p99 latency exceeded 50ms SLA!');
    process.exit(1);
  }
}

runLoadBenchmark();
```

---

## Troubleshooting & Best Practices

1. **Always Use `node:assert/strict`**
   Never use legacy `node:assert`. Strict mode ensures that `assert.equal(1, '1')` throws a type error rather than performing legacy loose type coercion.

2. **Ephemeral Ports for Integration Tests**
   Always listen on port `0` in integration tests (`server.listen(0)`). The OS kernel assigns an available unused port, allowing tests to run in parallel without `EADDRINUSE` port collision errors.
