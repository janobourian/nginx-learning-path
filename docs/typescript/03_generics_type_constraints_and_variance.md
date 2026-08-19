# Module 03: Generics, Type Constraints & Type Variance

**Track:** TypeScript — Enterprise Type System
**Category:** Type-Level Abstraction & Variance Theory

---

## 1. What Are Generics and Why Are They Essential?

In statically typed languages, writing reusable code presents a dilemma:

- If you use concrete types (`number`, `string`), a function is restricted to that single type.
- If you use `any` or `unknown`, you lose type safety and input-to-output relationship tracking.

**Generics** introduce **Type Variables** (e.g., `<T>`, `<K, V>`, `<TData, TError>`) that act as placeholders for types to be provided or inferred when the function, class, or interface is invoked.

Generics preserve the precise identity of types across function parameters, return values, and data structures:

```typescript
// Without Generics: Loss of type identity
function identityAny(arg: any): any {
  return arg; // Return type is 'any'; caller loses autocomplete and safety
}

// With Generics: Type identity is preserved
function identity<T>(arg: T): T {
  return arg; // Return type matches the EXACT input type T
}

const str = identity("hello"); // Type inferred as "hello" (string literal)
const num = identity(42);      // Type inferred as 42 (number literal)
```

---

## 2. Generic Functions, Interfaces, Aliases & Classes

### 1. Generic Functions with Multiple Type Parameters

```typescript
// Pair mapping function
function zip<A, B>(listA: A[], listB: B[]): [A, B][] {
  const minLength = Math.min(listA.length, listB.length);
  const result: [A, B][] = [];
  for (let i = 0; i < minLength; i++) {
    result.push([listA[i]!, listB[i]!]);
  }
  return result;
}

const pairs = zip(["a", "b", "c"], [1, 2, 3]);
// Inferred type: [string, number][]
```

### 2. Generic Result Monad (Enterprise Error Handling Pattern)

```typescript
export type Result<T, E = Error> =
  | { success: true; value: T }
  | { success: false; error: E };

export function Ok<T>(value: T): Result<T, never> {
  return { success: true, value };
}

export function Err<E>(error: E): Result<never, E> {
  return { success: false, error };
}

// Consuming the Generic Result
async function fetchUserSafe(id: string): Promise<Result<{ id: string; name: string }, string>> {
  try {
    const res = await fetch(`/api/users/${id}`);
    if (!res.ok) return Err(`User ${id} not found in database`);
    const data = await res.json();
    return Ok(data);
  } catch (e) {
    return Err((e as Error).message);
  }
}
```

---

## 3. Generic Constraints (`extends`)

By default, an unconstrained generic `<T>` can be *anything* (`unknown`). If you need to access properties on `T` (like `.length`, `.id`, or `.toISOString()`), you must constrain `T` using the `extends` keyword.

### 1. Property-Based Constraints

```typescript
interface HasLength {
  length: number;
}

// T is constrained to any type that has a .length property (arrays, strings, buffers)
function logLength<T extends HasLength>(item: T): T {
  console.log(`Length is: ${item.length}`);
  return item;
}

logLength("TypeScript");       // Valid: string has length
logLength([1, 2, 3, 4]);       // Valid: Array has length
logLength({ length: 10, w: 5 }); // Valid: Structurally has length
// logLength(123);             // ❌ Compile Error: 'number' has no 'length' property.
```

### 2. The `K extends keyof T` Pattern (Type-Safe Property Lookup)

To access an object's property safely by key without losing type precision:

```typescript
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

const user = {
  id: "u_101",
  name: "Alice",
  age: 30,
  roles: ["admin", "editor"],
};

const userName = getProperty(user, "name");   // Type: string
const userAge = getProperty(user, "age");     // Type: number
const userRoles = getProperty(user, "roles"); // Type: string[]
// getProperty(user, "email"); // ❌ Compile Error: Argument of type '"email"' is not assignable to parameter of type '"id" | "name" | "age" | "roles"'.
```

### 3. Generic Defaults (`<T = DefaultType>`)

Provide fallback types when the caller does not specify them and inference is not possible:

```typescript
interface ApiResponse<TData = Record<string, unknown>, TMeta = { timestamp: number }> {
  data: TData;
  meta: TMeta;
  statusCode: number;
}

// Uses default types:
const genericResponse: ApiResponse = {
  data: { foo: "bar" },
  meta: { timestamp: Date.now() },
  statusCode: 200,
};

// Overrides with custom types:
const typedResponse: ApiResponse<{ userId: string }, { cached: boolean; timestamp: number }> = {
  data: { userId: "123" },
  meta: { cached: true, timestamp: Date.now() },
  statusCode: 200,
};
```

---

## 4. Generic Variance Deep Dive

**Type Variance** describes how the subtyping relationship between complex generic types (`F<Sub>` and `F<Super>`) relates to the subtyping relationship between their constituent components (`Sub` and `Super`).

Given: `Dog extends Animal` (Subtype `Dog` is assignable to Supertype `Animal`):

```text
┌─────────────────┬──────────────────────────────────┬─────────────────────────────┐
│ Variance Mode   │ Mathematical Relation            │ Common TypeScript Scenario  │
├─────────────────┼──────────────────────────────────┼─────────────────────────────┤
│ **Covariant**   │ `F<Dog> extends F<Animal>`       │ Output positions (Return    │
│                 │ (Same direction)                 │ types, readonly properties) │
├─────────────────┼──────────────────────────────────┼─────────────────────────────┤
│ **Contravariant**│ `F<Animal> extends F<Dog>`      │ Input positions (Function   │
│                 │ (Reversed direction)             │ parameters under strict)    │
├─────────────────┼──────────────────────────────────┼─────────────────────────────┤
│ **Invariant**   │ Neither extends the other        │ Mutable read/write property │
│                 │ (Strict identity required)       │ positions                   │
├─────────────────┼──────────────────────────────────┼─────────────────────────────┤
│ **Bivariant**   │ Both extend each other           │ Method signature shorthand  │
│                 │ (Permissive compatibility)       │ (legacy JS compatibility)   │
└─────────────────┴──────────────────────────────────┴─────────────────────────────┘
```

### 1. Covariance (Output Positions)

A generic type is **covariant** in type parameter `T` if `T` appears **only in output positions** (e.g. function return types or `readonly` properties):

```typescript
class Animal { name = "Animal"; }
class Dog extends Animal { bark() { return "Woof"; } }

interface Producer<T> {
  produce(): T; // T is in OUTPUT position -> Covariant
}

let dogProducer: Producer<Dog> = { produce: () => new Dog() };
let animalProducer: Producer<Animal> = dogProducer; // ✅ Covariant assignment valid!
// Calling animalProducer.produce() returns a Dog, which is a valid Animal.
```

### 2. Contravariance (Input Positions under `strictFunctionTypes`)

A generic type is **contravariant** in type parameter `T` if `T` appears **in input positions** (function arguments):

```typescript
interface Consumer<T> {
  consume(item: T): void; // T is in INPUT position -> Contravariant
}

let animalConsumer: Consumer<Animal> = { consume: (a: Animal) => console.log(a.name) };
let dogConsumer: Consumer<Dog> = animalConsumer; // ✅ Contravariant assignment valid!

// Why does this work?
// dogConsumer only ever passes Dog instances to consume().
// animalConsumer knows how to handle ANY Animal (including Dogs). Therefore, it is safe!

// ❌ The reverse is NOT safe and blocked by TypeScript:
// let unsafeAnimalConsumer: Consumer<Animal> = dogConsumer; // Error!
// unsafeAnimalConsumer could pass a Cat to dogConsumer, which expects Dog.bark()!
```

---

## 5. Explicit Variance Annotations (`in` / `out` in TS 4.7+)

TypeScript automatically calculates variance by structural analysis, but for deeply recursive generic types, this structural check is computationally expensive. You can provide explicit variance hints to speed up `tsc` type-checking performance:

```typescript
// 'out T': Explicitly tells compiler T is Covariant (Output only)
type ReadOnlyList<out T> = {
  get(index: number): T;
};

// 'in T': Explicitly tells compiler T is Contravariant (Input only)
type Logger<in T> = {
  log(value: T): void;
};

// 'in out T': Explicitly marks T as Invariant (Both Input and Output)
type MutableStore<in out T> = {
  get(): T;
  set(value: T): void;
};
```

---

## 6. Real-World Architecture: Strongly-Typed Event Bus

```typescript
export type EventMap = Record<string, unknown>;

export class TypedEventEmitter<TEvents extends EventMap> {
  private listeners = new Map<keyof TEvents, Set<(payload: any) => void>>();

  public on<K extends keyof TEvents>(event: K, listener: (payload: TEvents[K]) => void): () => void {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    const set = this.listeners.get(event)!;
    set.add(listener);

    // Return cleanup unsubscribe function
    return () => set.delete(listener);
  }

  public emit<K extends keyof TEvents>(event: K, payload: TEvents[K]): void {
    const set = this.listeners.get(event);
    if (set) {
      set.forEach((fn) => fn(payload));
    }
  }
}

// Consuming the Typed Event Bus
interface ApplicationEvents {
  "user:login": { userId: string; timestamp: number };
  "order:created": { orderId: string; totalAmount: number; currency: "USD" | "EUR" };
  "system:alert": { severity: "low" | "high" | "critical"; message: string };
}

const bus = new TypedEventEmitter<ApplicationEvents>();

// Autocomplete and strict payload verification!
bus.on("user:login", (payload) => {
  console.log(`User ${payload.userId} logged in at ${payload.timestamp}`);
});

bus.emit("order:created", {
  orderId: "ord_999",
  totalAmount: 199.95,
  currency: "USD",
});
```

---

## Troubleshooting & Best Practices

1. **Do not create generic parameters when they are used only once**

   ```typescript
   // ❌ Unnecessary generic:
   function printName<T extends { name: string }>(obj: T): void {
     console.log(obj.name);
   }

   // ✅ Cleaner signature:
   function printName(obj: { name: string }): void {
     console.log(obj.name);
   }
   ```

2. **Always enable `strictFunctionTypes: true`**
   Without `strictFunctionTypes`, function parameter checking is bivariant (permissive), which can allow runtime type errors when passing derived function signatures.
