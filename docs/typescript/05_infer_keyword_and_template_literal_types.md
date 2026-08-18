# Module 05: The `infer` Keyword & Template Literal Types

**Track:** TypeScript — Enterprise Type System  
**Category:** Type Extraction, Pattern Matching & String Metaprogramming

---

## 1. What Is the `infer` Keyword?

In conditional types, the `extends` clause lets you check if a type matches a specific structural shape. The **`infer`** keyword allows you to **declare a brand new type variable** within that shape and **extract (capture)** whatever type occupied that position.

Think of `infer` as pattern matching and regex capture groups, but operating directly on static types at compile time:

```typescript
type ExtractReturnType<T> = T extends (...args: any[]) => infer R ? R : never;
```

If `T` is a function, TypeScript pattern-matches its return type, binds it to the new type variable `R`, and returns `R`.

---

## 2. Practical Type Extractions with `infer`

### 1. Extracting Function Return Types (`ReturnType<T>`)

```typescript
type CustomReturnType<T> = T extends (...args: any[]) => infer R ? R : never;

function getUser() {
  return { id: "123", name: "Alice", active: true };
}

type User = CustomReturnType<typeof getUser>;
// Inferred as: { id: string; name: string; active: boolean }
```

### 2. Extracting Function Parameters (`Parameters<T>`)

```typescript
type CustomParameters<T> = T extends (...args: infer P) => any ? P : never;

function updateProfile(userId: string, data: { email: string; age?: number }, notify: boolean) {
  return true;
}

type UpdateArgs = CustomParameters<typeof updateProfile>;
// Inferred as: [userId: string, data: { email: string; age?: number }, notify: boolean] (Tuple)
```

### 3. Recursive Promise Unwrapping (`Awaited<T>`)

Extracting the resolved payload from deeply nested Promises:

```typescript
type CustomAwaited<T> = T extends null | undefined
  ? T
  : T extends PromiseLike<infer U>
  ? CustomAwaited<U> // Recursive unwrapping for Promise<Promise<string>>
  : T;

type A = CustomAwaited<Promise<string>>;                 // string
type B = CustomAwaited<Promise<Promise<number[]>>>;      // number[]
type C = CustomAwaited<boolean>;                         // boolean
```

### 4. Tuple Pattern Matching (Head, Tail & Last Element)

```typescript
// 1. Extract the First Element of a Tuple (Head)
export type Head<T extends any[]> = T extends [infer First, ...any[]] ? First : never;

// 2. Extract the Remaining Elements (Tail)
export type Tail<T extends any[]> = T extends [any, ...infer Rest] ? Rest : [];

// 3. Extract the Last Element
export type Last<T extends any[]> = T extends [...any[], infer Final] ? Final : never;

type SampleTuple = ["first", 2, true, { name: "last" }];

type Item1 = Head<SampleTuple>; // "first"
type ItemTail = Tail<SampleTuple>; // [2, true, { name: "last" }]
type ItemLast = Last<SampleTuple>; // { name: "last" }
```

---

## 3. Template Literal Types

Introduced in TypeScript 4.1, **Template Literal Types** use the same syntax as JavaScript template strings (`` `prefix_${string}` ``) to compute and manipulate string literal types at compile time.

### Built-in String Manipulation Utilities

TypeScript includes four built-in compiler intrinsic types for string transformation:

```typescript
type S = "helloWorld";

type Upper = Uppercase<S>;     // "HELLOWORLD"
type Lower = Lowercase<S>;     // "helloworld"
type Cap   = Capitalize<S>;    // "HelloWorld"
type Uncap = Uncapitalize<Cap>;// "helloWorld"
```

---

## 4. Union Multiplications with Template Literals

When multiple union types are interpolated into a template literal, TypeScript automatically computes the **Cartesian product** of all possible combinations:

```typescript
type SemanticColor = "primary" | "secondary" | "danger" | "success";
type Size = "sm" | "md" | "lg";

// Generates all 12 permutations automatically:
type ButtonClass = `btn-${SemanticColor}-${Size}`;
// Result: "btn-primary-sm" | "btn-primary-md" | "btn-primary-lg" | "btn-secondary-sm" | ...
```

### Auto-Generating Event Handler Names

```typescript
type EntityEvent = "create" | "update" | "delete" | "archive";
type Entity = "User" | "Order" | "Product";

// Generates: "onUserCreate" | "onUserUpdate" | "onOrderDelete" | ...
type EventListenerName = `on${Entity}${Capitalize<EntityEvent>}`;

interface EnterpriseEventHandlers {
  onUserCreate(user: { id: string }): void;
  onUserDelete(id: string): void;
  onOrderCreate(order: { total: number }): void;
}
```

---

## 5. Advanced Pattern: Route Parameter Extraction with `infer` & Template Literals

One of the most powerful real-world applications of template literal types and `infer` is building type-safe routing frameworks (such as tRPC or Express type wrappers).

We can parse a string route path like `"/users/:userId/posts/:postId"` and automatically extract `{ userId: string; postId: string }` as a strictly typed object!

```typescript
// Type that recursively extracts parameter names starting with ':'
export type ExtractRouteParams<TPath extends string> =
  TPath extends `${string}:${infer Param}/${infer Rest}`
    ? { [K in Param | keyof ExtractRouteParams<`/${Rest}`>]: string }
    : TPath extends `${string}:${infer Param}`
    ? { [K in Param]: string }
    : Record<string, never>;

// Testing the Type Parser:
type UserPostRoute = "/orgs/:orgId/users/:userId/posts/:postId";
type Params = ExtractRouteParams<UserPostRoute>;
// Inferred as:
// {
//   orgId: string;
//   userId: string;
//   postId: string;
// }

// Implementing a Type-Safe Router Function:
function makeGetRequest<TPath extends string>(
  path: TPath,
  params: ExtractRouteParams<TPath>
): Promise<Response> {
  let resolvedUrl: string = path;
  for (const [key, value] of Object.entries(params)) {
    resolvedUrl = resolvedUrl.replace(`:${key}`, encodeURIComponent(value as string));
  }
  return fetch(resolvedUrl);
}

// Consuming the API:
makeGetRequest("/orgs/:orgId/users/:userId/posts/:postId", {
  orgId: "acme_corp",
  userId: "user_42",
  postId: "post_999",
  // extra: "invalid", // ❌ Compile Error: Object literal may only specify known properties!
});
```

---

## 6. Advanced Pattern: Type-Safe Nested Object Path Indexing

Creating type-safe dot-notation paths for accessing deeply nested state properties (similar to `lodash.get` or Vue/React form field bindings):

```typescript
// Generates all valid dot-separated paths for a nested object:
export type NestedObjectPaths<T> = T extends object
  ? {
      [K in keyof T & string]: T[K] extends Array<any>
        ? K
        : T[K] extends object
        ? `${K}` | `${K}.${NestedObjectPaths<T[K]>}`
        : `${K}`;
    }[keyof T & string]
  : never;

// Resolves the type at a given dot path:
export type PathValue<T, P extends string> =
  P extends `${infer Key}.${infer Rest}`
    ? Key extends keyof T
      ? PathValue<T[Key], Rest>
      : never
    : P extends keyof T
    ? T[P]
    : never;

// Example Usage:
interface AppConfig {
  database: {
    postgres: {
      host: string;
      port: number;
      ssl: boolean;
    };
    redis: {
      url: string;
    };
  };
  server: {
    port: number;
  };
}

type ConfigPaths = NestedObjectPaths<AppConfig>;
// "server" | "database" | "server.port" | "database.postgres" |
// "database.postgres.host" | "database.postgres.port" | ...

function getNestedConfig<P extends ConfigPaths>(
  config: AppConfig,
  path: P
): PathValue<AppConfig, P> {
  const keys = path.split(".");
  let current: any = config;
  for (const key of keys) {
    current = current[key];
  }
  return current;
}

const config: AppConfig = {
  database: { postgres: { host: "localhost", port: 5432, ssl: true }, redis: { url: "redis://localhost" } },
  server: { port: 3000 },
};

const host = getNestedConfig(config, "database.postgres.host"); // Type: string
const port = getNestedConfig(config, "database.postgres.port"); // Type: number
// getNestedConfig(config, "database.invalid.path"); // ❌ Compile Error: Argument not assignable to ConfigPaths!
```

---

## Troubleshooting & Best Practices

1. **Avoid unbound `infer` in non-matching branches**
   An inferred variable `R` is only available within the *true* branch of the conditional type (`T extends ... ? (R is valid here) : (R is invalid here)`).

2. **Template literal recursion depth**
   Deeply nested string splits on massive strings (e.g. parsing 500 lines of CSV at the type level) will trigger `TS2589: Type instantiation is excessively deep`. Keep template literal string parsing focused on API paths, identifiers, and configuration keys.
