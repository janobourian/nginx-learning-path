# Module 07: Testing, Benchmarking & Documentation

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Quality Assurance & Developer Tooling

---

## Testing in Deno — Zero Configuration

Deno's built-in test runner requires no packages, no configuration, and no separate tooling. You write test files and run `deno test`. The runner discovers test files by convention: any file ending in `_test.ts`, `.test.ts`, or inside a `__tests__/` directory.

---

## `Deno.test()` — The Basic Building Block

```typescript
// math_test.ts
import { assertEquals, assertThrows, assertRejects } from "@std/assert";

// Simplest form: name and function
Deno.test("addition is commutative", () => {
  assertEquals(1 + 2, 2 + 1);
});

// Async test
Deno.test("fetch returns JSON", async () => {
  const response = await fetch("https://api.example.com/status");
  const data = await response.json() as { status: string };
  assertEquals(data.status, "ok");
});

// Test with options object — gives you fine-grained control
Deno.test({
  name: "reads config file",
  permissions: { read: ["./config.json"] },  // Only grant what this test needs
  fn: async () => {
    const config = await Deno.readTextFile("./config.json");
    const parsed = JSON.parse(config);
    assertEquals(typeof parsed.port, "number");
  },
});

// Ignore a test temporarily (like xit in Jest)
Deno.test({
  name: "feature not yet implemented",
  ignore: true,
  fn: () => {
    // will be skipped
  },
});

// Mark a test as the only one to run in this file (for debugging)
Deno.test({
  name: "the only test that runs",
  only: true,  // Other tests in this file are skipped
  fn: () => {
    assertEquals(1, 1);
  },
});
```

---

## BDD-Style Tests with `@std/testing/bdd`

For developers who prefer the `describe/it` pattern familiar from Jest and Mocha:

```typescript
// user_service_test.ts
import { describe, it, beforeAll, afterAll, beforeEach } from "@std/testing/bdd";
import { assertEquals, assertExists, assertRejects } from "@std/assert";
import { UserService } from "./user_service.ts";

// Stub database type for tests
interface TestDb {
  users: Map<string, { id: string; name: string; email: string; passwordHash: string }>;
  close(): void;
}

function createTestDb(): TestDb {
  return {
    users: new Map(),
    close() {},
  };
}

describe("UserService", () => {
  let db: TestDb;
  let service: UserService;

  beforeAll(() => {
    db = createTestDb();
    service = new UserService(db);
  });

  afterAll(() => {
    db.close();
  });

  beforeEach(() => {
    db.users.clear();
  });

  describe("createUser()", () => {
    it("creates a user with a hashed password", async () => {
      const user = await service.createUser({
        name: "Alice",
        email: "alice@example.com",
        password: "hunter2",
      });

      assertExists(user.id);
      assertEquals(user.name, "Alice");
      assertEquals(user.email, "alice@example.com");
      // Password should never be stored in plain text
      assertNotEquals(user.passwordHash, "hunter2");
    });

    it("rejects duplicate emails", async () => {
      await service.createUser({ name: "Bob", email: "bob@example.com", password: "pass" });

      await assertRejects(
        () => service.createUser({ name: "Bob2", email: "bob@example.com", password: "pass2" }),
        Error,
        "Email already registered",
      );
    });

    it("rejects empty names", async () => {
      await assertRejects(
        () => service.createUser({ name: "", email: "x@example.com", password: "pass" }),
        Error,
        "Name cannot be empty",
      );
    });
  });

  describe("authenticate()", () => {
    it("returns user for correct credentials", async () => {
      await service.createUser({ name: "Carol", email: "carol@example.com", password: "secret" });
      const user = await service.authenticate("carol@example.com", "secret");
      assertExists(user);
      assertEquals(user.email, "carol@example.com");
    });

    it("returns null for wrong password", async () => {
      await service.createUser({ name: "Dave", email: "dave@example.com", password: "correct" });
      const user = await service.authenticate("dave@example.com", "wrong");
      assertEquals(user, null);
    });
  });
});
```

---

## Test Mocking and Spying with `@std/testing/mock`

```typescript
import { spy, stub, assertSpyCalls, assertSpyCallArgs, returnsNext } from "@std/testing/mock";
import { describe, it, beforeEach } from "@std/testing/bdd";
import { assertEquals } from "@std/assert";

describe("EmailNotifier", () => {
  it("sends email on user registration", async () => {
    // Create a spy on the sendEmail function
    const sendEmailSpy = spy(async (_to: string, _subject: string) => {});

    const notifier = new EmailNotifier({ sendEmail: sendEmailSpy });
    await notifier.onUserRegistered({ id: "1", email: "alice@example.com", name: "Alice" });

    // Verify the spy was called exactly once
    assertSpyCalls(sendEmailSpy, 1);

    // Verify it was called with the right arguments
    assertSpyCallArgs(sendEmailSpy, 0, [
      "alice@example.com",
      "Welcome to our service, Alice!",
    ]);
  });

  it("retries on transient email failure", async () => {
    // stub: returns values in sequence — first call fails, second succeeds
    const sendEmailStub = stub(
      emailClient,
      "send",
      returnsNext([
        Promise.reject(new Error("SMTP timeout")),
        Promise.resolve(undefined),
      ])
    );

    try {
      const notifier = new EmailNotifier({ emailClient });
      await notifier.sendWithRetry("alice@example.com", "Test");

      assertSpyCalls(sendEmailStub, 2);  // Was retried once
    } finally {
      sendEmailStub.restore();  // Always restore stubs
    }
  });
});

// Stub declaration helpers
const emailClient = {
  send: async (_to: string, _subject: string) => {},
};

// Stubs for external types
declare class EmailNotifier {
  constructor(deps: { sendEmail?: typeof spy; emailClient?: typeof emailClient });
  onUserRegistered(user: { id: string; email: string; name: string }): Promise<void>;
  sendWithRetry(to: string, subject: string): Promise<void>;
}

function assertNotEquals<T>(a: T, b: T): void {
  if (a === b) throw new Error(`Expected ${a} to not equal ${b}`);
}
```

---

## Code Coverage

```bash

# Run tests and collect coverage data
deno test --coverage=coverage_data

# Generate a text report
deno coverage coverage_data

# Generate an LCOV report (for CI systems like Codecov, Coveralls)
deno coverage coverage_data --lcov --output=coverage.lcov

# Generate an HTML report
deno coverage coverage_data --html

# Open coverage/index.html in a browser
```

Coverage output example:

```text
cover https://example.com/mod.ts ... 95.24% (40/42)
cover https://example.com/utils.ts ... 100.00% (23/23)
cover https://example.com/db.ts ... 71.43% (10/14)
```

---

## Benchmarking with `Deno.bench()`

`Deno.bench()` is the built-in benchmarking API. Run with `deno bench`.

```typescript
// string_bench.ts
import { encodeBase64 } from "@std/encoding/base64";

const sampleData = new Uint8Array(1024).fill(0xAB);
const sampleString = "Hello, World!".repeat(100);

// Basic benchmark
Deno.bench("base64 encode 1KB", () => {
  encodeBase64(sampleData);
});

// Benchmark with setup
Deno.bench({
  name: "JSON parse large object",
  fn() {
    JSON.parse('{"users":[' + Array(100).fill('{"id":1,"name":"Alice","active":true}').join(",") + "]}");
  },
});

// Group related benchmarks for comparison
Deno.bench({ name: "concat: string +", group: "string concat", baseline: true }, () => {
  let result = "";
  for (let i = 0; i < 1000; i++) result += "x";
});

Deno.bench({ name: "concat: array join", group: "string concat" }, () => {
  const parts: string[] = [];
  for (let i = 0; i < 1000; i++) parts.push("x");
  parts.join("");
});

Deno.bench({ name: "concat: template literal", group: "string concat" }, () => {
  let result = "";
  for (let i = 0; i < 1000; i++) result = `${result}x`;
});
```

```bash
deno bench string_bench.ts
```

Output:

```text
benchmark                   time/iter (avg)        iter/s      (min … max)
--------------------------- ------------------- ----------- ---------------
base64 encode 1KB                   542 ns     1,845,018 (530 ns … 601 ns)
JSON parse large object             8.3 µs       120,048 (7.9 µs … 9.1 µs)

group string concat
concat: string +          (baseline)
concat: array join           1.1x faster
concat: template literal     1.0x faster
```

---

## JSDoc Documentation with `deno doc`

Deno generates documentation from JSDoc comments in your source files:

```typescript
/**

 * Computes the SHA-256 hash of a string.
 *

 * @param input - The string to hash.
 * @returns A hex-encoded SHA-256 digest.
 *

 * @example
 * ```ts
 * const hash = await sha256("Hello, World!");
 * console.log(hash); // "dffd6..."
 * ```
 */
export async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**

 * Represents a paginated response from the API.
 *

 * @template T - The type of items in the page.
 */
export interface PagedResponse<T> {
  /** The items in the current page. */
  items: T[];
  /** Total number of items across all pages. */
  total: number;
  /** Current page number, 1-indexed. */
  page: number;
  /** Number of items per page. */
  pageSize: number;
  /** Whether there are more pages after this one. */
  hasNextPage: boolean;
}
```

```bash

# Show docs in the terminal
deno doc mod.ts

# Generate JSON documentation (useful for tooling)
deno doc --json mod.ts > docs.json

# Generate HTML documentation
deno doc --html --output=docs/ mod.ts
```

---

## `deno.json` Tasks for Quality Checks

```json
{
  "tasks": {
    "test": "deno test --allow-net=localhost --allow-read=./fixtures tests/",
    "test:coverage": "deno test --coverage=cov_profile && deno coverage cov_profile",
    "bench": "deno bench benchmarks/",
    "check": "deno check src/main.ts",
    "lint": "deno lint",
    "fmt": "deno fmt",
    "ci": "deno fmt --check && deno lint && deno check src/main.ts && deno test"
  }
}
```

The `ci` task runs everything in sequence: formatting check, lint, type check, then tests. Exit code is non-zero if any step fails, making it suitable as a CI gate.

---

## Troubleshooting

### Tests pass locally but fail in CI with permission errors

CI runs without `-A`. Enumerate the exact permissions your tests need in the `deno test` command or in per-test `permissions` objects. Run locally with the same flags as CI to reproduce.

### `deno bench` shows high variance results

Benchmarks are sensitive to JIT warmup and CPU throttling. Use `--warmup` to run warmup iterations, and ensure your machine isn't under CPU throttling during benchmarks. The `(min … max)` column in the output shows spread — high variance indicates inconsistent results.

### Coverage shows 0% for a file that clearly runs during tests

Ensure the file is imported at least once by the test suite. Files that are never imported don't appear in coverage. Also confirm the file is under the coverage collection path.
