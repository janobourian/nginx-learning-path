# Module 01: Primitive Types, Interfaces, Type Aliases & Top/Bottom Types

**Track:** TypeScript — Enterprise Type System  
**Category:** Type System Fundamentals & Type Theory

---

## 1. The TypeScript Type Universe & Type Lattice

In type theory, types represent sets of possible values. TypeScript's type system forms a mathematical lattice bounded by **Top Types** (sets containing all possible values) and **Bottom Types** (the empty set containing no values).

```
                     ┌────────────────────────┐
                     │      unknown / any     │  ◄── TOP TYPES (All possible values)
                     └───────────┬────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         ▼                       ▼                       ▼
    ┌──────────┐           ┌──────────┐           ┌──────────┐
    │  string  │           │  number  │           │  object  │  ◄── PRIMITIVE & OBJECT TYPES
    └────┬─────┘           └────┬─────┘           └────┬─────┘
         │                      │                      │
         ▼                      ▼                      ▼
    ┌──────────┐           ┌──────────┐           ┌──────────┐
    │  "admin" │           │    42    │           │  {id:1}  │  ◄── LITERAL TYPES (Subsets)
    └────┬─────┘           └────┬─────┘           └────┬─────┘
         │                      │                      │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                     ┌────────────────────────┐
                     │         never          │  ◄── BOTTOM TYPE (Empty set / ∅)
                     └────────────────────────┘
```

---

## 2. Primitive Types

TypeScript has 7 core primitive types corresponding directly to JavaScript's `typeof` operators:

```typescript
// 1. string: UTF-16 character sequences
const username: string = "Alice";
const greeting: string = `Hello, ${username}`;

// 2. number: IEEE 754 double-precision 64-bit floats (integers, floats, NaN, Infinity)
const count: number = 42;
const price: number = 19.99;
const hex: number = 0xff;
const binary: number = 0b1010;

// 3. boolean: true or false
const isActive: boolean = true;
const hasPermission: boolean = false;

// 4. bigint: Arbitrary precision integers (ES2020+)
const maxSafeInt: bigint = 9007199254740991n;
const hugeValue: bigint = BigInt("9007199254740991000000");

// 5. symbol: Globally unique, immutable identifiers
const UniqueKey: symbol = Symbol("unique_id");
const record = { [UniqueKey]: "confidential_data" };

// 6. null: Intentional absence of any object value
const selectedCustomer: string | null = null;

// 7. undefined: Variable has been declared but not assigned a value
let pendingPayload: object | undefined = undefined;
```

---

## 3. Top Types & Bottom Types: `unknown`, `any`, `void`, `never`

### 1. `unknown` (The Safe Top Type)

`unknown` is the type-safe counterpart of `any`. Everything is assignable to `unknown`, but `unknown` is **not assignable to anything else** (except `unknown` and `any`) without explicit type narrowing:

```typescript
function parseNetworkData(raw: unknown): string {
  // ❌ Compile Error: 'raw' is of type 'unknown'.
  // return raw.trim();

  // ✅ Type Narrowing required:
  if (typeof raw === "string") {
    return raw.trim(); // Safe! TypeScript knows raw is string here.
  }

  if (raw instanceof Error) {
    return raw.message;
  }

  return "Unknown Data Format";
}
```

### 2. `any` (The Escape Hatch — Unsafe)

`any` disables all type checking. It turns off the compiler's safety guarantees and should be strictly avoided or restricted to legacy migration boundaries:

```typescript
let dangerous: any = "Hello";
dangerous = 42;
dangerous.nonExistentMethod(); // Compiles fine, but crashes with TypeError at runtime!
```

### 3. `void` (Absence of Return Value)

`void` denotes the return type of functions that do not return a value (they return `undefined` implicitly):

```typescript
function logSystemEvent(event: string): void {
  console.log(`[EVENT]: ${event}`);
  // return undefined; // Valid in void functions
}
```

### 4. `never` (The Bottom Type & Exhaustiveness Checking)

`never` represents the type of values that **never occur**:
- A function that throws an error and never returns.
- A function with an infinite event loop.
- The resulting type when all members of a union have been narrowed away.

```typescript
// Function that never returns:
function terminateProcess(message: string): never {
  throw new Error(`Fatal Crash: ${message}`);
}

// Enterprise Pattern: Exhaustive Switch Checking
type PaymentMethod = "credit_card" | "paypal" | "crypto" | "apple_pay";

function processPayment(method: PaymentMethod, amount: number): void {
  switch (method) {
    case "credit_card":
      console.log(`Charging CC: $${amount}`);
      break;
    case "paypal":
      console.log(`Routing to PayPal: $${amount}`);
      break;
    case "crypto":
      console.log(`Broadcasting transaction: $${amount}`);
      break;
    case "apple_pay":
      console.log(`Apple Pay checkout: $${amount}`);
      break;
    default: {
      // If a new payment method is added to PaymentMethod union (e.g. 'google_pay')
      // but not handled in this switch, TypeScript will throw a compile error here!
      const _exhaustiveCheck: never = method;
      throw new Error(`Unhandled payment method: ${_exhaustiveCheck}`);
    }
  }
}
```

---

## 4. Interfaces vs Type Aliases

Both `interface` and `type` can describe the shape of objects, but they have distinct trade-offs and specific use cases.

| Feature | `interface` | `type` Alias |
| :--- | :--- | :--- |
| **Object Shape Declaration** | `interface User { name: string }` | `type User = { name: string }` |
| **Declaration Merging** | **Yes** (Multiple declarations merge automatically) | **No** (Duplicate identifier error) |
| **Union & Intersection Types** | No direct union (`interface X = A \| B` invalid) | **Yes** (`type Status = "A" \| "B"`) |
| **Primitives, Tuples, Literals** | No (Objects/Functions only) | **Yes** (`type ID = string \| number`) |
| **Inheritance Syntax** | `interface B extends A {}` | `type B = A & { extra: string }` |
| **Class `implements` Support** | **Yes** (`class C implements I {}`) | **Yes** (`class C implements T {}`) |
| **Compiler Performance** | Slightly faster for large object hierarchies (cached by name) | Evaluated structurally |

### 1. Interface Declaration Merging (Augmenting Third-Party Types)

Interfaces automatically merge when declared with the same name. This is fundamental for **module augmentation** (e.g., adding properties to `window`, `process.env`, or third-party libraries):

```typescript
// First declaration:
interface UserProfile {
  id: string;
  name: string;
}

// Second declaration in a different file or plugin:
interface UserProfile {
  role: "admin" | "member";
  avatarUrl?: string;
}

// The resulting UserProfile interface has all 4 properties:
const user: UserProfile = {
  id: "u_1",
  name: "Alice",
  role: "admin",
  avatarUrl: "https://example.com/avatar.png",
};
```

### 2. Type Aliases for Complex Unions, Tuples, and Computed Types

```typescript
// Union Types (Impossible with interface)
type HttpMethod = "GET" | "POST" | "PUT" | "DELETE" | "PATCH";
type Result<T> = { success: true; data: T } | { success: false; error: Error };

// Tuple Types
type GeoCoordinate = [latitude: number, longitude: number, altitude?: number];
const location: GeoCoordinate = [37.7749, -122.4194];

// Function Signature Alias
type EventListener<T> = (event: T) => void | Promise<void>;
```

---

## 5. Union & Intersection Types (`|`, `&`)

### 1. Union Types (`|`) — Logical OR (Sum Types)

A union type represents a value that can be one of several types:

```typescript
type Identifier = string | number;

function formatId(id: Identifier): string {
  if (typeof id === "number") {
    return `ID-${id.toFixed(0).padStart(6, "0")}`;
  }
  return id.toUpperCase();
}
```

### 2. Intersection Types (`&`) — Logical AND (Product Types)

An intersection combines multiple types into one containing all members of each constituent type:

```typescript
interface Timestamps {
  createdAt: Date;
  updatedAt: Date;
}

interface SoftDeletable {
  deletedAt?: Date;
  isDeleted: boolean;
}

interface Article {
  id: string;
  title: string;
  body: string;
}

// Combining entities with intersection
type DatabaseArticle = Article & Timestamps & SoftDeletable;

const post: DatabaseArticle = {
  id: "art_101",
  title: "TypeScript Enterprise Guide",
  body: "Deep dive into type systems...",
  createdAt: new Date(),
  updatedAt: new Date(),
  isDeleted: false,
};
```

---

## 6. Type Assertions & `as const`

### 1. Type Assertions (`as Type`)

Type assertions tell the compiler: *"Trust me, I know the runtime type of this value better than you do."* Use assertions cautiously, as they override compiler verification:

```typescript
const searchInput = document.getElementById("search-box") as HTMLInputElement;
searchInput.value = "TypeScript"; // Accessible because it's asserted to HTMLInputElement
```

### 2. `const` Assertions (`as const`)

`as const` constructs deep **readonly literal types** instead of widening values to `string`, `number`, or general arrays:

```typescript
// Without 'as const': Widened to string and string[]
const config1 = {
  endpoint: "https://api.example.com",
  ports: [80, 443],
};
// Type: { endpoint: string; ports: number[] }

// With 'as const': Deeply immutable literal types
const config2 = {
  endpoint: "https://api.example.com",
  ports: [80, 443],
} as const;
// Type: { readonly endpoint: "https://api.example.com"; readonly ports: readonly [80, 443] }

// config2.endpoint = "other"; // Error: Cannot assign to 'endpoint' because it is a read-only property.
```

---

## 7. Excess Property Checks

When assigning an object literal directly to an interface or type, TypeScript applies **Excess Property Checking** to catch typos:

```typescript
interface RequestOptions {
  timeout?: number;
  retries?: number;
}

function fetchWithRetry(url: string, options: RequestOptions) {}

// ❌ Error: Object literal may only specify known properties, and 'retrys' does not exist in type 'RequestOptions'.
// fetchWithRetry("/api/data", { timeout: 5000, retrys: 3 }); // Catches the typo 'retrys'!

// ✅ Bypassing excess checks (via variable reference):
const rawOptions = { timeout: 5000, retrys: 3, extraMetadata: "debug" };
fetchWithRetry("/api/data", rawOptions); // Allowed because rawOptions is a structurally compatible object
```

---

## Troubleshooting & Best Practices

1. **Never use the uppercase wrapper types `String`, `Number`, `Boolean`, `Object`**
   Always use lowercase primitives: `string`, `number`, `boolean`, `object`. The uppercase versions refer to JavaScript non-primitive object wrappers.

2. **Avoid `any` by defaulting to `unknown`**
   Whenever accepting dynamic JSON payloads, unparsed strings, or unknown third-party data, type the variable as `unknown` and use user-defined type guards (Module 08) or validation schemas (Zod).

3. **Prefer `interface` for public APIs and data models; prefer `type` for unions and utility types.**
