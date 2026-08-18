# Module 04: Advanced Type-Level Programming & Conditional Types

**Track:** TypeScript — Enterprise Type System  
**Category:** Type-Level Metaprogramming & Type Computation

---

## 1. What Are Conditional Types?

In JavaScript, ternary expressions (`condition ? a : b`) perform decision logic at runtime. In TypeScript, **Conditional Types** introduce this exact same branching mechanism directly into the **type system** at compile time:

```typescript
type ConditionalType<T, U, X, Y> = T extends U ? X : Y;
```

If the type `T` is assignable to type `U`, the resulting type resolves to `X`; otherwise, it resolves to `Y`.

This unlocks Turing-complete type-level metaprogramming: calculating complex return types, extracting nested generic payloads, transforming data models, and constructing compile-time logic gates.

---

## 2. Basic Conditional Types & Type Narrowing

```typescript
// Example: Converting primitive types to their corresponding metadata label
type TypeLabel<T> =
  T extends string ? "string_type" :
  T extends number ? "number_type" :
  T extends boolean ? "boolean_type" :
  T extends (...args: any[]) => any ? "function_type" :
  "object_type";

type A = TypeLabel<"hello">;   // "string_type"
type B = TypeLabel<42>;        // "number_type"
type C = TypeLabel<() => void>;// "function_type"
```

---

## 3. Distributive Conditional Types (Union Distribution)

When a conditional type operates on a **naked type parameter** `T`, and `T` is given a **Union Type** (`A | B | C`), the conditional type automatically **distributes over each member of the union**:

$$\text{Type}<A \mid B \mid C> \iff \text{Type}<A> \mid \text{Type}<B> \mid \text{Type}<C>$$

### Example: How `Exclude<T, U>` Works Internally

The built-in utility type `Exclude<T, U>` is implemented with a single distributive conditional type:

```typescript
type CustomExclude<T, U> = T extends U ? never : T;

type AvailableColors = "red" | "green" | "blue" | "yellow";
type Filtered = CustomExclude<AvailableColors, "red" | "blue">;
// Step-by-step distribution evaluation:
// ("red" extends "red" | "blue" ? never : "red")      -> never
// | ("green" extends "red" | "blue" ? never : "green")  -> "green"
// | ("blue" extends "red" | "blue" ? never : "blue")    -> never
// | ("yellow" extends "red" | "blue" ? never : "yellow")-> "yellow"
// Result: never | "green" | never | "yellow" => "green" | "yellow"
```

Notice that `never` automatically dissolves in union types ($X \cup \emptyset = X$).

---

## 4. Preventing Union Distribution (Tuple Wrapping)

Sometimes you want to test whether the **entire union as a whole** satisfies a constraint, rather than testing each member individually. 

To turn off distribution, wrap both the type parameter and target type in square brackets `[T] extends [U]`:

```typescript
// Distributive:
type ToArrayDistributive<T> = T extends any ? T[] : never;
type TestDist = ToArrayDistributive<string | number>;
// Result: string[] | number[]

// Non-Distributive (Tuple Wrapped):
type ToArrayNonDistributive<T> = [T] extends [any] ? T[] : never;
type TestNonDist = ToArrayNonDistributive<string | number>;
// Result: (string | number)[]
```

---

## 5. Type-Level Logic Gates & Type Predicates

We can implement pure boolean logic gates entirely at the type level:

```typescript
// ─── 1. Logic Gates ───
export type If<TCond extends boolean, TThen, TElse> = TCond extends true ? TThen : TElse;
export type Not<T extends boolean> = T extends true ? false : true;
export type And<A extends boolean, B extends boolean> = A extends true ? (B extends true ? true : false) : false;
export type Or<A extends boolean, B extends boolean> = A extends true ? true : (B extends true ? true : false);

// ─── 2. Type Equality Check (Strict Type Comparison) ───
// Relies on conditional type parameter assignability rules
export type Equals<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends
  (<T>() => T extends Y ? 1 : 2) ? true : false;

// ─── 3. IsNever<T> Type Check ───
// Must be non-distributive because never distributed produces never!
export type IsNever<T> = [T] extends [never] ? true : false;

// ─── 4. IsAny<T> Type Check ───
// any is special: 0 extends (1 & any) is only true for any
export type IsAny<T> = 0 extends (1 & T) ? true : false;

// ─── 5. IsUnknown<T> Type Check ───
export type IsUnknown<T> = IsAny<T> extends true ? false : [unknown] extends [T] ? true : false;
```

---

## 6. Recursive Conditional Types

Starting in TypeScript 4.1, conditional types can directly reference themselves recursively.

### 1. `DeepReadonly<T>` (Immutable Deep Clone of Any Data Structure)

```typescript
export type DeepReadonly<T> = T extends Function | boolean | number | string | symbol | null | undefined
  ? T
  : T extends Array<infer U>
  ? ReadonlyArray<DeepReadonly<U>>
  : T extends Map<infer K, infer V>
  ? ReadonlyMap<DeepReadonly<K>, DeepReadonly<V>>
  : T extends Set<infer M>
  ? ReadonlySet<DeepReadonly<M>>
  : T extends object
  ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
  : T;

// Usage:
interface UserProfile {
  name: string;
  metadata: {
    permissions: string[];
    settings: {
      theme: string;
    };
  };
}

type ImmutableUser = DeepReadonly<UserProfile>;
// Everything down to permissions[0] and settings.theme is deeply readonly!
```

### 2. Flattening Nested Arrays (`Flatten<T>`)

```typescript
export type Flatten<T> = T extends Array<infer Item>
  ? Flatten<Item>
  : T;

type NestedNumbers = [1, [2, [3, [4, [5]]]]];
type Flat = Flatten<NestedNumbers>; // Inferred as: 1 | 2 | 3 | 4 | 5
```

### 3. Strongly Typed JSON Schema Validator

```typescript
export type JsonPrimitive = string | number | boolean | null;
export type JsonArray = JsonValue[];
export type JsonObject = { [key: string]: JsonValue };
export type JsonValue = JsonPrimitive | JsonObject | JsonArray;

// Validates that a given type is 100% JSON-serializable
export type MustBeJson<T> = T extends JsonValue
  ? T
  : "Error: Type contains non-JSON serializable values (functions, undefined, symbols, bigints)";

function sendJsonPayload<T>(payload: MustBeJson<T>): void {
  fetch("/api/data", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

sendJsonPayload({ user: "Alice", active: true, scores: [10, 20] }); // ✅ Valid
// sendJsonPayload({ user: "Bob", callback: () => {} }); // ❌ Compile Error: Type contains non-JSON serializable values
```

---

## 7. Real-World Architecture: Dynamic Database Query Builder Typing

```typescript
interface DatabaseSchema {
  users: { id: string; name: string; email: string; age: number };
  posts: { id: string; userId: string; title: string; content: string; published: boolean };
  comments: { id: string; postId: string; text: string };
}

// Conditional extraction of valid table column names:
type TableColumns<TTable extends keyof DatabaseSchema> = keyof DatabaseSchema[TTable];

// Dynamic SQL SELECT Builder Return Type
type QueryResult<
  TTable extends keyof DatabaseSchema,
  TColumns extends TableColumns<TTable>[]
> = {
  [K in TColumns[number]]: DatabaseSchema[TTable][K];
};

function selectFrom<
  TTable extends keyof DatabaseSchema,
  TColumns extends TableColumns<TTable>[]
>(
  table: TTable,
  columns: TColumns
): Promise<QueryResult<TTable, TColumns>[]> {
  return fetch(`/api/db?table=${table}&cols=${columns.join(",")}`).then((r) => r.json());
}

// Consuming the Query Builder:
const users = await selectFrom("users", ["id", "email"]);
// Inferred Return Type: { id: string; email: string; }[]
// Accessing users[0].age throws a compile error because 'age' was not selected!
```

---

## Troubleshooting & Compiler Limits

1. **`Type instantiation is excessively deep and possibly infinite (TS2589)`**
   - TypeScript has a built-in recursion limit (~1,000 recursive steps) to prevent compiler hangs.
   - For recursive types, always ensure there is a clear base case that resolves to non-recursive primitives.

2. **Unexpected Union Distribution with `never`**
   - If `T` in `T extends U ? X : Y` is passed `never`, the entire expression evaluates to `never` without reaching `Y` because distribution over the empty set produces the empty set. Use `[T] extends [never]` to detect `never`.
