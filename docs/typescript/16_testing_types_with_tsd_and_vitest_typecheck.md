# Module 16: Type Testing — `tsd` & Vitest `expectTypeOf`

**Track:** TypeScript — Enterprise Type System
**Category:** Type Quality Assurance & Compiler-Level Testing

---

## 1. Why Test Types?

When building utility libraries, SDKs, design systems, or enterprise domain models, **unit testing runtime JavaScript is only half the battle**.

Consider a generic type utility like `DeepReadonly<T>` or an API router like `tRPC`:

- Runtime tests verify that functions return the correct JavaScript values.
- **Type tests** verify that the compiler computes the exact expected static types, catches illegal assignments, and emits compile errors when given invalid arguments.

Without automated type testing, updating a type utility can cause silent breaking type regressions across hundreds of consuming packages.

---

## 2. The Type Testing Ecosystem: `tsd` vs Vitest Typecheck

| Tool | Engine | Best For | Syntax Style |
| :--- | :--- | :--- | :--- |
| **`tsd`** | Standalone CLI | Testing published `.d.ts` declaration packages | `expectType<T>(val)`, `expectError(val)` |
| **Vitest `typecheck`** | Vitest Test Runner | Integrated monorepo and full-stack projects | `expectTypeOf<T>().toEqualTypeOf<U>()` |

---

## 3. Type Testing with Vitest `expectTypeOf`

Vitest includes first-class type testing support out of the box via `expectTypeOf`.

### 1. Enabling Typecheck in `vitest.config.ts`

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    typecheck: {
      enabled: true, // Run typecheck suite alongside unit tests
      checker: "tsc",
    },
  },
});
```

### 2. Writing Comprehensive Type Assertions

```typescript
// test/types/typeAssertions.spec.ts
import { describe, it, expectTypeOf } from "vitest";
import type { DeepReadonly, ExtractRouteParams, Result } from "@/types";

describe("Type-Level Test Suite", () => {
  it("verifies DeepReadonly makes nested properties immutable", () => {
    type Source = {
      id: string;
      meta: { tags: string[] };
    };

    type Target = DeepReadonly<Source>;

    // Strict type equality:
    expectTypeOf<Target>().toEqualTypeOf<{
      readonly id: string;
      readonly meta: {
        readonly tags: readonly string[];
      };
    }>();

    // Verify properties are not assignable to mutable variants:
    expectTypeOf<Target>().not.toMatchTypeOf<Source>();
  });

  it("verifies ExtractRouteParams extracts dynamic path parameters", () => {
    type Path = "/users/:userId/posts/:postId";
    type Extracted = ExtractRouteParams<Path>;

    expectTypeOf<Extracted>().toEqualTypeOf<{
      userId: string;
      postId: string;
    }>();
  });

  it("verifies function argument and return types", () => {
    function processUser(id: string, options?: { sendEmail?: boolean }): Promise<{ success: boolean }> {
      return Promise.resolve({ success: true });
    }

    // Inspect function parameters:
    expectTypeOf(processUser).toBeFunction();
    expectTypeOf(processUser).parameter(0).toBeString();
    expectTypeOf(processUser).parameter(1).toEqualTypeOf<{ sendEmail?: boolean } | undefined>();

    // Inspect resolved async return type:
    expectTypeOf(processUser).returns.resolves.toEqualTypeOf<{ success: boolean }>();
  });

  it("verifies Result Monad discriminants", () => {
    type AuthResult = Result<{ token: string }, Error>;

    // Verify Assignability:
    expectTypeOf<{ success: true; value: { token: string } }>().toBeAssignableTo<AuthResult>();
    expectTypeOf<{ success: false; error: Error }>().toBeAssignableTo<AuthResult>();

    // Invalid discriminant is NOT assignable:
    expectTypeOf<{ success: "maybe"; value: null }>().not.toBeAssignableTo<AuthResult>();
  });
});
```

---

## 4. Type Testing with `tsd`

`tsd` is the industry standard for testing declaration files in open-source TypeScript packages.

```bash
npm install -D tsd
```

Create a test file ending in `.test-d.ts`:

```typescript
// test/index.test-d.ts
import { expectType, expectAssignable, expectNotAssignable, expectError } from "tsd";
import { formatCurrency, SafeRequestBuilder } from "../src/index.js";

// 1. Exact Type Equality:
expectType<string>(formatCurrency(19.99, "USD"));

// 2. Assignability Checks:
interface BaseEntity { id: string }
interface UserEntity { id: string; name: string }

expectAssignable<BaseEntity>({ id: "1", name: "Alice" } as UserEntity);
expectNotAssignable<UserEntity>({ id: "1" } as BaseEntity);

// 3. Testing That Compiler Errors Are Thrown on Illegal Invocations:
// Calling .build() on an unconfigured builder MUST throw a compile error:
expectError(SafeRequestBuilder.create().build());

// Passing invalid arguments MUST throw a compile error:
expectError(formatCurrency("invalid_number", "USD"));
```

Run the `tsd` CLI:

```bash
npx tsd
```

Output:

```text
✔ All type definitions pass type checks!
```

---

## 5. Automated CI/CD Type Testing Workflow

```yaml

# .github/workflows/type-test.yml
name: Type Regression & Verification

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  type-tests:
    runs-on: ubuntu-latest
    steps:

      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'

      - name: Install Dependencies
        run: npm ci

      - name: Static Type Check (tsc --noEmit)
        run: npx tsc --noEmit

      - name: Run Vitest Typecheck Suite
        run: npx vitest typecheck --run

      - name: Run TSD Package Test
        run: npx tsd
```

---

## Troubleshooting & Best Practices

1. **`toEqualTypeOf` vs `toMatchTypeOf` in Vitest**

   - `toEqualTypeOf<A>()`: Requires **exact bidirectional structural identity** ($A \subseteq B \land B \subseteq A$).
   - `toMatchTypeOf<A>()`: Requires **unidirectional assignability** (Subtyping / $A \subseteq B$).

2. **Negative Type Tests (`@ts-expect-error` vs `@ts-ignore`)**
   Always use `// @ts-expect-error` instead of `// @ts-ignore`. If a bug is fixed or types change such that the line is no longer an error, `@ts-expect-error` alerts you with an unused directive error!
