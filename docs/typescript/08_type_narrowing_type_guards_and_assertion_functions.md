# Module 08: Type Narrowing, User-Defined Type Guards & Assertion Functions

**Track:** TypeScript — Enterprise Type System  
**Category:** Control Flow Analysis & Runtime Validation

---

## 1. Control Flow Analysis (CFA)

TypeScript uses **Control Flow Analysis (CFA)** to track the type of a variable at every step of execution. When code branches via `if`, `switch`, loops, or early returns, the compiler inspects conditions and **narrows** broad types (`string | number | null`, `unknown`, `Animal | Vehicle`) to specific subtypes.

```typescript
function processInput(input: string | number | Date | null) {
  // Here: input is string | number | Date | null

  if (input === null) {
    return; // Early return
  }
  // Here: input is narrowed to string | number | Date (null removed)

  if (typeof input === "string") {
    console.log(input.toUpperCase()); // Narrowed to 'string'
  } else if (typeof input === "number") {
    console.log(input.toFixed(2));    // Narrowed to 'number'
  } else {
    console.log(input.toISOString());  // Narrowed to 'Date'
  }
}
```

---

## 2. Built-in Type Guards

### 1. `typeof` Guards

Narrows JavaScript primitive types: `"string"`, `"number"`, `"boolean"`, `"bigint"`, `"symbol"`, `"undefined"`, `"function"`, `"object"`.

*Note: `typeof null === "object"` in JavaScript, so `typeof x === "object"` does not exclude `null`.*

```typescript
function padLeft(padding: number | string, input: string): string {
  if (typeof padding === "number") {
    return " ".repeat(padding) + input;
  }
  return padding + input; // Narrowed to 'string'
}
```

### 2. `instanceof` Guards

Narrows instances of ES6 classes or constructor functions by checking the prototype chain:

```typescript
class NetworkError extends Error {
  constructor(public statusCode: number, message: string) {
    super(message);
  }
}

class ValidationError extends Error {
  constructor(public field: string, message: string) {
    super(message);
  }
}

function handleApiError(error: unknown) {
  if (error instanceof NetworkError) {
    console.error(`HTTP Status ${error.statusCode}: ${error.message}`);
  } else if (error instanceof ValidationError) {
    console.error(`Validation failed on field "${error.field}": ${error.message}`);
  } else if (error instanceof Error) {
    console.error(`Generic error: ${error.message}`);
  } else {
    console.error("Unknown runtime exception", error);
  }
}
```

### 3. The `in` Operator Guard

Checks for the existence of a property on an object union:

```typescript
interface AdminUser {
  id: string;
  role: "admin";
  manageDatabase(): void;
}

interface MemberUser {
  id: string;
  role: "member";
  viewFeed(): void;
}

type User = AdminUser | MemberUser;

function routeUser(user: User) {
  if ("manageDatabase" in user) {
    user.manageDatabase(); // Narrowed to AdminUser
  } else {
    user.viewFeed();       // Narrowed to MemberUser
  }
}
```

---

## 3. Discriminated Unions (Tagged Unions)

A **Discriminated Union** is an algebraic data type pattern where all union members share a common literal property (the **discriminant** / **tag**). This is the gold standard for modeling state machines, redux actions, network events, and AST nodes.

```typescript
interface LoadingState {
  status: "loading";
}

interface SuccessState<T> {
  status: "success";
  data: T;
  receivedAt: Date;
}

interface ErrorState {
  status: "error";
  error: Error;
  retryCount: number;
}

type AsyncState<T> = LoadingState | SuccessState<T> | ErrorState;

function renderUI<T>(state: AsyncState<T>): string {
  switch (state.status) {
    case "loading":
      return "Loading spinner...";
    case "success":
      // TypeScript automatically narrows state to SuccessState<T>!
      return `Data loaded at ${state.receivedAt.toISOString()}: ${JSON.stringify(state.data)}`;
    case "error":
      // Narrowed to ErrorState!
      return `Error (${state.retryCount} retries): ${state.error.message}`;
  }
}
```

---

## 4. User-Defined Type Guards (`val is TargetType`)

When validation logic spans multiple checks or is encapsulated in a helper function, standard functions lose type narrowing when they return a plain `boolean`. 

A **User-Defined Type Guard** uses the type predicate syntax `parameterName is Type` as its return type annotation:

```typescript
interface CustomerOrder {
  orderId: string;
  items: { sku: string; qty: number }[];
  total: number;
}

// User-Defined Type Guard:
export function isCustomerOrder(obj: unknown): obj is CustomerOrder {
  if (typeof obj !== "object" || obj === null) return false;

  const candidate = obj as Record<string, unknown>;

  return (
    typeof candidate.orderId === "string" &&
    Array.isArray(candidate.items) &&
    typeof candidate.total === "number" &&
    candidate.items.every(
      (item) =>
        typeof item === "object" &&
        item !== null &&
        typeof item.sku === "string" &&
        typeof item.qty === "number"
    )
  );
}

// Consuming the Type Guard:
async function processIncomingWebhook(payload: unknown) {
  if (isCustomerOrder(payload)) {
    // payload is 100% safely narrowed to CustomerOrder!
    console.log(`Processing Order ${payload.orderId} with total $${payload.total}`);
  } else {
    throw new Error("Invalid Webhook Payload Format");
  }
}
```

---

## 5. Assertion Functions (`asserts condition` & `asserts val is T`)

Introduced in TypeScript 3.7, **Assertion Functions** throw an exception if a condition is not met. If the function returns normally without throwing, the compiler assumes the condition is true for the rest of the surrounding scope:

```typescript
// 1. Invariant Assertion Function
export function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(`Assertion Failure: ${message}`);
  }
}

// 2. Type-Narrowing Assertion Function
export function assertIsString(val: unknown): asserts val is string {
  if (typeof val !== "string") {
    throw new Error(`Expected string, but received ${typeof val}`);
  }
}

// Usage in Business Logic:
function handleUserProfile(profileName: unknown) {
  // profileName is 'unknown' here

  assertIsString(profileName);
  
  // profileName is automatically narrowed to 'string' for all subsequent lines!
  console.log(profileName.trim().toUpperCase());
}
```

---

## 6. The `satisfies` Operator (TypeScript 4.9+)

Before `satisfies`, you had to choose between two imperfect options when typing configuration objects:
1. **Type Annotation (`const obj: Schema = ...`)**: Enforces the schema, but **widens** specific literals (e.g. `"red"` becomes `string`, losing exact autocomplete).
2. **No Annotation**: Preserves specific literal types, but fails to catch missing or misspelled schema properties.

The **`satisfies`** operator validates that an expression matches a type **without changing or widening the resulting type**:

```typescript
type Color = "red" | "green" | "blue";
type CustomRGB = [r: number, g: number, b: number];

type ThemePalette = Record<string, Color | CustomRGB>;

// Using 'satisfies':
const palette = {
  primary: "red",
  secondary: [0, 255, 128],
  accent: "blue",
} satisfies ThemePalette;

// 1. Catches invalid values at compile time:
// const badPalette = { primary: "yellow" } satisfies ThemePalette; // ❌ Compile Error!

// 2. Retains exact literal and tuple types!
palette.primary.toUpperCase(); // Inferred as 'red' (string method available!)
palette.secondary.map((c) => c * 2); // Inferred as [number, number, number] (Array methods available!)
```

---

## Troubleshooting & Best Practices

1. **Beware of false positives in user-defined type guards**
   TypeScript completely trusts your `obj is Type` predicate. If your boolean logic inside the guard is buggy or incomplete (e.g. forgetting to check `obj !== null`), runtime crashes will still occur despite valid compile checks.

2. **Always prefer Discriminated Unions over multiple boolean flags**
   ```typescript
   // ❌ Anti-pattern: Impossible states possible
   interface State {
     isLoading: boolean;
     isError: boolean;
     data: any;
     error: Error | null;
   }

   // ✅ Best Practice: Discriminated Union
   type State =
     | { status: "idle" }
     | { status: "loading" }
     | { status: "success"; data: any }
     | { status: "error"; error: Error };
   ```
