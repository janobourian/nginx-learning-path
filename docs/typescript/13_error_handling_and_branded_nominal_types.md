# Module 13: Error Handling & Branded Nominal Types

**Track:** TypeScript — Enterprise Type System
**Category:** Nominal Modeling, Domain-Driven Design & Functional Error Handling

---

## 1. The Limitation of Structural Typing (Primitive Obsession)

Because TypeScript is structurally typed, any two types that share the same shape are completely interchangeable. While this provides great flexibility, it causes severe domain modeling vulnerabilities known as **Primitive Obsession**:

```typescript
// All these domain concepts are structurally just 'string':
type UserId = string;
type OrderId = string;
type EmailAddress = string;

function sendOrderConfirmationEmail(userId: UserId, orderId: OrderId, email: EmailAddress): void {
  console.log(`Sending email to ${email} for order ${orderId} (User: ${userId})`);
}

const user = "usr_999";
const order = "ord_111";
const email = "alice@example.com";

// ❌ DANGEROUS BUG: Arguments passed in the wrong order!
// TypeScript compiles this with ZERO warnings because all 3 parameters are structurally 'string':
sendOrderConfirmationEmail(email, user, order);
// Runtime output: "Sending email to ord_111 for order usr_999 (User: alice@example.com)" -> Corrupted email delivery!
```

---

## 2. Branded Types (Nominal Typing via Phantom Tags)

**Branded Types** (also known as Tagged, Opaque, or Flavored types) attach an unforgeable compile-time brand to a primitive type without altering its runtime representation or adding runtime memory overhead.

### The Standard Branding Utility

```typescript
declare const __brand: unique symbol;

export type Brand<TBase, TBrandName extends string> = TBase & {
  readonly [__brand]: TBrandName;
};
```

---

## 3. Creating Domain-Driven Branded Primitives

```typescript
// 1. Defining Branded Domain Types
export type UserId = Brand<string, "UserId">;
export type OrderId = Brand<string, "OrderId">;
export type EmailAddress = Brand<string, "EmailAddress">;
export type UsdCents = Brand<number, "UsdCents">;
export type ValidatedJsonString = Brand<string, "ValidatedJsonString">;

// 2. Smart Constructors & Type-Safe Validators
export function parseUserId(raw: string): UserId {
  if (!raw.startsWith("usr_")) {
    throw new Error(`Invalid UserId format: ${raw}`);
  }
  return raw as UserId;
}

export function parseOrderId(raw: string): OrderId {
  if (!raw.startsWith("ord_")) {
    throw new Error(`Invalid OrderId format: ${raw}`);
  }
  return raw as OrderId;
}

export function parseEmail(raw: string): EmailAddress {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(raw)) {
    throw new Error(`Invalid Email Address format: ${raw}`);
  }
  return raw as EmailAddress;
}

export function toUsdCents(dollars: number): UsdCents {
  if (dollars < 0) throw new Error("Amount cannot be negative");
  return Math.round(dollars * 100) as UsdCents;
}
```

### Compiler Verification with Branded Types

```typescript
function sendOrderConfirmationEmail(
  userId: UserId,
  orderId: OrderId,
  email: EmailAddress
): void {
  console.log(`Sending email to ${email} for order ${orderId} (User: ${userId})`);
}

const safeUser = parseUserId("usr_999");
const safeOrder = parseOrderId("ord_111");
const safeEmail = parseEmail("alice@example.com");

// ✅ Valid: Arguments match exact branded nominal types
sendOrderConfirmationEmail(safeUser, safeOrder, safeEmail);

// ❌ Compile Error: Caught at compile time!
// sendOrderConfirmationEmail(safeEmail, safeUser, safeOrder);
// Error: Type 'EmailAddress' is not assignable to type 'UserId'.
// Type 'EmailAddress' is missing the following properties from type 'UserId': [__brand]
```

---

## 4. Functional Error Handling without Exceptions (`Result` Monad)

Traditional `try/catch` error handling has significant flaws in TypeScript:

1. Functions that throw do **not** declare their thrown exceptions in their type signatures.
2. Caught errors in `catch (err)` are typed as `unknown` / `any`.
3. Unhandled exceptions crash server processes.

The **`Result<T, E>` pattern** represents errors as **values** returned explicitly from functions.

```typescript
// src/utils/result.ts

export type Result<T, E = Error> = Ok<T> | Err<E>;

export class Ok<T> {
  readonly success = true as const;
  constructor(public readonly value: T) {}

  isOk(): this is Ok<T> { return true; }
  isErr(): this is Err<never> { return false; }

  map<U>(fn: (val: T) => U): Result<U, never> {
    return new Ok(fn(this.value));
  }

  flatMap<U, E2>(fn: (val: T) => Result<U, E2>): Result<U, E2> {
    return fn(this.value);
  }

  unwrap(): T {
    return this.value;
  }
}

export class Err<E> {
  readonly success = false as const;
  constructor(public readonly error: E) {}

  isOk(): this is Ok<never> { return false; }
  isErr(): this is Err<E> { return true; }

  map<U>(_fn: (val: never) => U): Result<never, E> {
    return this as any;
  }

  flatMap<U, E2>(_fn: (val: never) => Result<U, E2>): Result<never, E> {
    return this as any;
  }

  unwrap(): never {
    if (this.error instanceof Error) throw this.error;
    throw new Error(String(this.error));
  }
}

// Helpers
export const ok = <T>(val: T): Result<T, never> => new Ok(val);
export const err = <E>(e: E): Result<never, E> => new Err(e);
```

---

## 5. Composing Business Logic with `Result` Pipelines

```typescript
interface UserRecord {
  id: UserId;
  email: EmailAddress;
  balanceCents: UsdCents;
}

// Domain Errors
type PaymentError =
  | { kind: "USER_NOT_FOUND"; userId: UserId }
  | { kind: "INSUFFICIENT_FUNDS"; currentBalance: UsdCents; required: UsdCents }
  | { kind: "GATEWAY_TIMEOUT"; message: string };

function findUser(id: UserId): Result<UserRecord, PaymentError> {
  if (id === "usr_404" as UserId) {
    return err({ kind: "USER_NOT_FOUND", userId: id });
  }
  return ok({
    id,
    email: "user@example.com" as EmailAddress,
    balanceCents: 5000 as UsdCents, // $50.00
  });
}

function debitUser(user: UserRecord, chargeAmount: UsdCents): Result<UserRecord, PaymentError> {
  if (user.balanceCents < chargeAmount) {
    return err({
      kind: "INSUFFICIENT_FUNDS",
      currentBalance: user.balanceCents,
      required: chargeAmount,
    });
  }
  return ok({
    ...user,
    balanceCents: (user.balanceCents - chargeAmount) as UsdCents,
  });
}

// Chaining Operations via flatMap:
function processCheckout(userId: UserId, itemPriceDollars: number): Result<UserRecord, PaymentError> {
  const chargeAmount = toUsdCents(itemPriceDollars);

  return findUser(userId)
    .flatMap((user) => debitUser(user, chargeAmount));
}

// Handling the Result:
const result = processCheckout(parseUserId("usr_123"), 29.99);

if (result.isOk()) {
  console.log(`Payment successful! New balance: $${(result.value.balanceCents / 100).toFixed(2)}`);
} else {
  const error = result.error;
  switch (error.kind) {
    case "USER_NOT_FOUND":
      console.error(`User ${error.userId} does not exist`);
      break;
    case "INSUFFICIENT_FUNDS":
      console.error(`Insufficient balance: needed $${error.required / 100}, had $${error.currentBalance / 100}`);
      break;
    case "GATEWAY_TIMEOUT":
      console.error(`Payment gateway timeout: ${error.message}`);
      break;
  }
}
```

---

## 6. Type-Safe `tryCatch` Wrapper

To interface cleanly with legacy Promise-based APIs that throw:

```typescript
export async function tryCatch<T, E = Error>(
  promise: Promise<T>,
  mapError: (err: unknown) => E = (err) => err as E
): Promise<Result<T, E>> {
  try {
    const data = await promise;
    return ok(data);
  } catch (rawError) {
    return err(mapError(rawError));
  }
}

// Usage:
const fetchResult = await tryCatch(
  fetch("https://api.example.com/orders").then((r) => r.json()),
  (err) => new Error(`Network failed: ${(err as Error).message}`)
);
```

---

## Troubleshooting & Best Practices

1. **Branded Types with JSON serialization**
   At runtime, a `UserId` is still just a plain JavaScript string (`"usr_123"`). When serialized via `JSON.stringify()`, it serializes normally without extra metadata properties.

2. **Always validate at system boundaries**
   Use smart constructor functions (`parseUserId`, `parseEmail`) at system boundaries (HTTP request handlers, database reads, message queue consumers) to transform raw unvalidated strings into safe Branded Types.
