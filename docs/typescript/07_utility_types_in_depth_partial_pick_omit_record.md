# Module 07: Built-in Utility Types in Depth — Internal Mechanics & Composition

**Track:** TypeScript — Enterprise Type System
**Category:** Standard Library Utilities & Custom Composition

---

## 1. The Standard Utility Type Library

TypeScript ships with a rich standard library of utility types defined in `lib.es5.d.ts`. Rather than magic compiler intrinsics, almost all utility types are pure TypeScript expressions built using generics, mapped types, conditional types, and `infer`.

Mastering both their usage and their internal source definitions allows you to combine and compose custom domain-specific utility types.

---

## 2. Object Manipulation Utility Types

### 1. `Partial<T>` & `Required<T>`

Makes all properties optional (`?`) or mandatory (`-?`):

```typescript
// Standard Library Definition:
type Partial<T> = {
  [P in keyof T]?: T[P];
};

type Required<T> = {
  [P in keyof T]-?: T[P];
};

// Usage:
interface UserDTO {
  id: string;
  email: string;
  bio?: string;
}

type UpdateUserPayload = Partial<UserDTO>;   // { id?: string; email?: string; bio?: string }
type StrictUser = Required<UserDTO>;         // { id: string; email: string; bio: string }
```

### 2. `Readonly<T>`

Prevents reassignment to all properties:

```typescript
// Standard Library Definition:
type Readonly<T> = {
  readonly [P in keyof T]: T[P];
};

const user: Readonly<UserDTO> = { id: "1", email: "a@b.com" };
// user.email = "c@d.com"; // ❌ Error: Cannot assign to 'email' because it is a read-only property.
```

### 3. `Record<K, T>`

Constructs an object type whose property keys are `K` and values are `T`:

```typescript
// Standard Library Definition:
type Record<K extends keyof any, T> = {
  [P in K]: T;
};

// Usage:
type Role = "admin" | "editor" | "viewer";
interface Permissions {
  canWrite: boolean;
  canDelete: boolean;
}

const rolePermissions: Record<Role, Permissions> = {
  admin: { canWrite: true, canDelete: true },
  editor: { canWrite: true, canDelete: false },
  viewer: { canWrite: false, canDelete: false },
};
```

### 4. `Pick<T, K>` & `Omit<T, K>`

Selects or removes specific keys from an object type:

```typescript
// Standard Library Definition:
type Pick<T, K extends keyof T> = {
  [P in K]: T[P];
};

type Omit<T, K extends keyof any> = Pick<T, Exclude<keyof T, K>>;

interface FullArticle {
  id: string;
  title: string;
  content: string;
  authorId: string;
  viewCount: number;
  createdAt: Date;
}

// Pick only display properties:
type ArticlePreview = Pick<FullArticle, "id" | "title" | "viewCount">;

// Omit internal tracking and generated properties for creation payload:
type CreateArticleInput = Omit<FullArticle, "id" | "viewCount" | "createdAt">;
```

---

## 3. Union Manipulation Utility Types

### 1. `Exclude<T, U>` & `Extract<T, U>`

Filters union types by excluding or retaining members assignable to `U`:

```typescript
// Standard Library Definition:
type Exclude<T, U> = T extends U ? never : T;
type Extract<T, U> = T extends U ? T : never;

type HttpStatusCode = 200 | 201 | 400 | 401 | 403 | 404 | 500 | 502;

type ClientError = Extract<HttpStatusCode, 400 | 401 | 403 | 404>; // 400 | 401 | 403 | 404
type NonError = Exclude<HttpStatusCode, 400 | 401 | 403 | 404 | 500 | 502>; // 200 | 201
```

### 2. `NonNullable<T>`

Excludes `null` and `undefined` from a union type:

```typescript
// Standard Library Definition:
type NonNullable<T> = T extends null | undefined ? never : T;

type RawInput = string | number | null | undefined;
type ValidatedInput = NonNullable<RawInput>; // string | number
```

---

## 4. Function & Constructor Utility Types

### 1. `Parameters<T>` & `ReturnType<T>`

```typescript
// Standard Library Definition:
type Parameters<T extends (...args: any) => any> = T extends (...args: infer P) => any ? P : never;
type ReturnType<T extends (...args: any) => any> = T extends (...args: any) => infer R ? R : any;

function createSession(userId: string, rememberMe: boolean, clientIp?: string): { token: string; expires: number } {
  return { token: "abc", expires: Date.now() + 3600 };
}

type SessionArgs = Parameters<typeof createSession>; // [userId: string, rememberMe: boolean, clientIp?: string]
type SessionReturn = ReturnType<typeof createSession>; // { token: string; expires: number }
```

### 2. `ConstructorParameters<T>` & `InstanceType<T>`

Extracts arguments and instance types from constructor functions or ES6 classes:

```typescript
// Standard Library Definition:
type ConstructorParameters<T extends abstract new (...args: any) => any> =
  T extends abstract new (...args: infer P) => any ? P : never;

type InstanceType<T extends abstract new (...args: any) => any> =
  T extends abstract new (...args: any) => infer R ? R : any;

class OrderManager {
  constructor(public readonly warehouseId: string, public maxRetries: number = 3) {}
  processOrder(orderId: string) { return true; }
}

type OrderManagerArgs = ConstructorParameters<typeof OrderManager>; // [warehouseId: string, maxRetries?: number]
type OrderManagerInstance = InstanceType<typeof OrderManager>;       // OrderManager
```

---

## 5. Asynchronous Utilities: `Awaited<T>`

Unwraps Promises and `PromiseLike` instances recursively (TypeScript 4.5+):

```typescript
// Standard Library Definition:
type Awaited<T> =
  T extends null | undefined ? T :
  T extends object & { then(onfulfilled: infer F, ...args: infer _): any }
    ? F extends ((value: infer V, ...args: infer _) => any)
      ? Awaited<V>
      : never
    : T;

async function fetchLeaderboard(): Promise<Promise<{ rank: number; name: string }[]>> {
  return Promise.resolve([{ rank: 1, name: "Alice" }]);
}

type LeaderboardData = Awaited<ReturnType<typeof fetchLeaderboard>>;
// { rank: number; name: string }[]
```

---

## 6. Composing Custom Enterprise Utility Types

By combining the primitive standard utilities, we can construct sophisticated enterprise helper types:

```typescript
// 1. StrictOmit: Omit that verifies keys actually exist on T (built-in Omit allows any key)
export type StrictOmit<T, K extends keyof T> = Pick<T, Exclude<keyof T, K>>;

// 2. OptionalKeys<T>: Extracts all keys of T that are optional
export type OptionalKeys<T> = {
  [K in keyof T]-?: {} extends Pick<T, K> ? K : never;
}[keyof T];

// 3. RequiredKeys<T>: Extracts all keys of T that are required
export type RequiredKeys<T> = {
  [K in keyof T]-?: {} extends Pick<T, K> ? never : K;
}[keyof T];

// 4. Nullable<T>: Wraps all properties to allow null
export type Nullable<T> = {
  [K in keyof T]: T[K] | null;
};

// 5. Diff<T, U>: Keys present in T but not in U
export type Diff<T, U> = Pick<T, Exclude<keyof T, keyof U>>;

// 6. Intersection<T, U>: Keys present in both T and U
export type Intersection<T, U> = Pick<T, Extract<keyof T, keyof U>>;
```

### Example Test of Custom Utilities

```typescript
interface Customer {
  id: string;
  name: string;
  phoneNumber?: string;
  shippingAddress?: string;
}

type OptKeys = OptionalKeys<Customer>; // "phoneNumber" | "shippingAddress"
type ReqKeys = RequiredKeys<Customer>; // "id" | "name"

// StrictOmit verification:
type CustomerWithoutId = StrictOmit<Customer, "id">; // Valid
// type InvalidOmit = StrictOmit<Customer, "nonExistentKey">; // ❌ Compile Error: 'nonExistentKey' is not assignable to keyof Customer!
```

---

## Troubleshooting & Best Practices

1. **`Omit` vs `StrictOmit`**
   The standard library's `Omit<T, K extends keyof any>` accepts arbitrary strings for `K` without checking if `K` exists on `T`. If a property is renamed on `T`, `Omit<T, "oldName">` will silently stop omitting anything without throwing a compile error. In production codebases, use `StrictOmit<T, K extends keyof T>`.

2. **`Pick` on Union Types (`Discriminated Unions`)**
   Applying `Pick<UnionA | UnionB, 'type' | 'commonField'>` strips away union-specific discriminator properties. Use distributive conditional types when picking from discriminated unions.
