# Module 06: Mapped Types, Index Access & Key Remapping (`as`)

**Track:** TypeScript — Enterprise Type System
**Category:** Type Transformation & Object Metaprogramming

---

## 1. Index Access Types (`T[K]`)

**Index Access Types** (also called lookup types) allow querying the type of a specific property or elements within an object, interface, tuple, or array:

```typescript
interface UserAccount {
  id: string;
  profile: {
    username: string;
    avatar: string;
    contact: {
      email: string;
      phone: string;
    };
  };
  roles: ("admin" | "moderator" | "user")[];
}

// 1. Single property lookup
type ProfileType = UserAccount["profile"]; // { username: string; avatar: string; contact: { ... } }

// 2. Nested property lookup
type EmailType = UserAccount["profile"]["contact"]["email"]; // string

// 3. Array / Tuple element lookup via [number]
type RoleType = UserAccount["roles"][number]; // "admin" | "moderator" | "user"

// 4. Union of all property value types via [keyof T]
type AllAccountValues = UserAccount[keyof UserAccount];
// string | { username: string; ... } | ("admin" | "moderator" | "user")[]
```

---

## 2. What Are Mapped Types?

When building enterprise applications, you frequently need to take an existing interface and transform every property according to a pattern:

- Make every property optional (`Partial<T>`)
- Make every property read-only (`Readonly<T>`)
- Wrap every property in an observable or getter function
- Generate validation error maps

**Mapped Types** iterate over a union of keys (usually `keyof T`) and produce a new object type:

```typescript
type Mapped<T> = {
  [K in keyof T]: T[K];
};
```

---

## 3. Mapping Modifiers (`+` / `-` for `readonly` and `?`)

You can add (`+`) or remove (`-`) the `readonly` and `?` (optional) modifiers during mapping. If no sign is specified, `+` is assumed.

```typescript
interface OriginalModel {
  readonly id: string;
  name: string;
  description?: string;
}

// 1. Make all properties Optional and Readonly (+? and +readonly)
type FrozenDraft<T> = {
  +readonly [K in keyof T]+?: T[K];
};
type Draft = FrozenDraft<OriginalModel>;
// { readonly id?: string; readonly name?: string; readonly description?: string }

// 2. Make all properties Required and Mutable (-? and -readonly)
type MutableComplete<T> = {
  -readonly [K in keyof T]-?: T[K];
};
type Complete = MutableComplete<OriginalModel>;
// { id: string; name: string; description: string } (id is now mutable, description is required!)
```

---

## 4. Key Remapping via `as` (TypeScript 4.1+)

Mapped types can transform the **keys** of the resulting object using the `as` clause.

### 1. Generating Getter and Setter Methods

```typescript
type UserFields = {
  name: string;
  age: number;
  isActive: boolean;
};

// Generates { getName(): string; getAge(): number; getIsActive(): boolean; }
export type GenerateGetters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};

// Generates { setName(val: string): void; setAge(val: number): void; ... }
export type GenerateSetters<T> = {
  [K in keyof T as `set${Capitalize<string & K>}`]: (value: T[K]) => void;
};

type UserGetters = GenerateGetters<UserFields>;
// {
//   getName: () => string;
//   getAge: () => number;
//   getIsActive: () => boolean;
// }
```

### 2. Filtering Keys with `as (Condition ? K : never)`

If a key remapping evaluates to `never`, TypeScript **drops that key completely from the resulting object type**!

This allows filtering object properties by value type:

```typescript
// 1. PickByValue<T, ValueType>: Pick only properties matching a specific type
export type PickByValue<T, ValueType> = {
  [K in keyof T as T[K] extends ValueType ? K : never]: T[K];
};

// 2. OmitByValue<T, ValueType>: Omit properties matching a specific type
export type OmitByValue<T, ValueType> = {
  [K in keyof T as T[K] extends ValueType ? never : K]: T[K];
};

interface ServiceDefinition {
  name: string;
  port: number;
  debugMode: boolean;
  init: () => Promise<void>;
  stop: () => void;
  restart: () => Promise<boolean>;
}

// Extract only the function methods:
type ServiceMethods = PickByValue<ServiceDefinition, Function>;
// {
//   init: () => Promise<void>;
//   stop: () => void;
//   restart: () => Promise<boolean>;
// }

// Extract only non-function configuration properties:
type ServiceConfig = OmitByValue<ServiceDefinition, Function>;
// {
//   name: string;
//   port: number;
//   debugMode: boolean;
// }
```

---

## 5. Enterprise Pattern: Type-Safe Form State & Validation Schema

```typescript
interface RegistrationForm {
  username: string;
  email: string;
  age: number;
  acceptTerms: boolean;
}

// 1. Validation Error Object: Maps every field to an optional error message string
export type FormErrors<T> = {
  [K in keyof T]?: string | null;
};

// 2. Touched/Dirty State: Maps every field to a boolean
export type FormTouched<T> = {
  [K in keyof T]: boolean;
};

// 3. Validator Function Map: Maps every field to a validator rule
export type FormValidators<T> = {
  [K in keyof T]?: (value: T[K], allValues: T) => string | null | undefined;
};

// Form Controller Class
export class FormController<T extends object> {
  public values: T;
  public errors: FormErrors<T> = {};
  public touched: FormTouched<T>;

  constructor(
    initialValues: T,
    private validators: FormValidators<T>
  ) {
    this.values = { ...initialValues };
    this.touched = Object.keys(initialValues).reduce((acc, key) => {
      (acc as any)[key] = false;
      return acc;
    }, {} as FormTouched<T>);
  }

  public setValue<K extends keyof T>(field: K, value: T[K]): void {
    this.values[field] = value;
    this.touched[field] = true;
    this.validateField(field);
  }

  public validateField<K extends keyof T>(field: K): boolean {
    const validator = this.validators[field];
    if (validator) {
      const error = validator(this.values[field], this.values);
      this.errors[field] = error ?? null;
      return !error;
    }
    return true;
  }

  public isValid(): boolean {
    return Object.values(this.errors).every((err) => !err);
  }
}

// Using the Strongly-Typed Form:
const form = new FormController<RegistrationForm>(
  { username: "", email: "", age: 18, acceptTerms: false },
  {
    username: (val) => (val.length < 3 ? "Username must be at least 3 chars" : null),
    email: (val) => (!val.includes("@") ? "Invalid email address" : null),
    age: (val) => (val < 18 ? "Must be at least 18 years old" : null),
  }
);

form.setValue("username", "al");
console.log(form.errors.username); // "Username must be at least 3 chars"
```

---

## 6. Deep Mutable & Deep Nullable

```typescript
// DeepMutable: Recursively removes readonly from all nested structures
export type DeepMutable<T> = {
  -readonly [K in keyof T]: T[K] extends object
    ? T[K] extends Function
      ? T[K]
      : DeepMutable<T[K]>
    : T[K];
};

// DeepNullable: Recursively allows null on all fields
export type DeepNullable<T> = {
  [K in keyof T]: T[K] extends object
    ? T[K] extends Function
      ? T[K] | null
      : DeepNullable<T[K]> | null
    : T[K] | null;
};
```

---

## Troubleshooting & Best Practices

1. **`keyof T & string` Pattern**
   `keyof T` can include `string`, `number`, and `symbol`. When using template literal key remapping (like `` `get${Capitalize<K>}` ``), TypeScript requires `K` to be a string. Intersect with string (`K in keyof T & string` or `Capitalize<string & K>`) to satisfy compiler constraints.

2. **Index Signatures in Mapped Types**
   If `T` has an index signature (`[key: string]: any`), `keyof T` includes `string | number`. Mapped types preserve index signatures unless filtered with `as`.
