# Module 02: Functions, Classes & Object-Oriented Design in TypeScript

**Track:** TypeScript — Enterprise Type System
**Category:** OOP Architecture & Function Signature Design

---

## 1. Advanced Function Typing

Functions are first-class citizens in TypeScript. Proper function typing ensures safe input validation, correct return value inference, and expressive overload signatures.

### Parameter Typing, Defaults, Optionals & Rest Parameters

```typescript
// 1. Basic typed function with optional & default parameters
function createHttpRequest(
  url: string,
  method: "GET" | "POST" | "PUT" | "DELETE" = "GET", // Default parameter
  headers?: Record<string, string>,                   // Optional parameter (string | undefined)
  timeout: number = 5000
): Promise<Response> {
  return fetch(url, {
    method,
    headers: headers ?? {},
    signal: AbortSignal.timeout(timeout),
  });
}

// 2. Rest parameters with typed tuples
function calculateTotal(taxRate: number, ...itemPrices: number[]): number {
  const subtotal = itemPrices.reduce((sum, price) => sum + price, 0);
  return Number((subtotal * (1 + taxRate)).toFixed(2));
}

calculateTotal(0.08, 19.99, 45.50, 9.99); // Subtotal + 8% tax
```

---

## 2. Function Overloads (Polymorphic Signatures)

In JavaScript, a single function can accept different argument types and return completely different results based on those arguments. In TypeScript, **Function Overloads** allow declaring multiple public function signatures backed by a single private implementation signature.

```typescript
// Overload Signature 1: Passing a timestamp number returns a Date object
function parseDate(timestamp: number): Date;

// Overload Signature 2: Passing an ISO string returns a Date object
function parseDate(isoString: string): Date;

// Overload Signature 3: Passing year, month, day returns a Date object
function parseDate(year: number, month: number, day: number): Date;

// Implementation Signature (Not directly callable by consumers; must satisfy all overloads)
function parseDate(arg1: number | string, arg2?: number, arg3?: number): Date {
  if (typeof arg1 === "number" && arg2 === undefined && arg3 === undefined) {
    return new Date(arg1);
  }
  if (typeof arg1 === "string") {
    const parsed = Date.parse(arg1);
    if (isNaN(parsed)) throw new Error(`Invalid date string: ${arg1}`);
    return new Date(parsed);
  }
  if (typeof arg1 === "number" && typeof arg2 === "number" && typeof arg3 === "number") {
    return new Date(arg1, arg2 - 1, arg3);
  }
  throw new Error("Invalid arguments provided to parseDate");
}

// Consuming the overloaded function:
const d1 = parseDate(1700000000000);        // Matches overload 1 -> Date
const d2 = parseDate("2026-08-18T00:00:00Z"); // Matches overload 2 -> Date
const d3 = parseDate(2026, 8, 18);          // Matches overload 3 -> Date
// parseDate("2026", 8); // ❌ Compile Error: No overload matches this call.
```

---

## 3. Explicit `this` Parameter Typing

In JavaScript, `this` is dynamically scoped based on how a function is called. TypeScript allows declaring a fictitious first parameter named `this` to strictly enforce what object context the function is allowed to run in (the `this` parameter is erased during compilation):

```typescript
interface DatabaseConnection {
  host: string;
  isConnected: boolean;
  connect(this: DatabaseConnection): void;
}

const db: DatabaseConnection = {
  host: "postgres-primary.internal",
  isConnected: false,
  connect(this: DatabaseConnection) {
    this.isConnected = true;
    console.log(`Connected to database at ${this.host}`);
  },
};

db.connect(); // Valid!

// ❌ Calling detached method unbound:
const standaloneConnect = db.connect;
// standaloneConnect(); // Error: The 'this' context of type 'void' is not assignable to method's 'this' of type 'DatabaseConnection'.
```

---

## 4. Classes & Object-Oriented Architecture

TypeScript transforms JavaScript classes into a robust object-oriented system with encapsulation, inheritance, abstract contracts, and parameter properties.

```typescript
export interface Identifiable {
  id: string;
}

export interface Auditable {
  createdAt: Date;
  updatedAt: Date;
}

// ─── 1. Abstract Base Class ───
export abstract class BaseEntity implements Identifiable, Auditable {
  // Parameter properties: Declaring 'public', 'private', or 'protected' in the constructor
  // automatically generates and assigns the class field!
  constructor(
    public readonly id: string,
    public readonly createdAt: Date = new Date(),
    public updatedAt: Date = new Date()
  ) {}

  // Abstract method: Derived classes MUST provide an implementation
  abstract validate(): boolean;

  // Concrete shared method
  public touch(): void {
    this.updatedAt = new Date();
  }
}
```

---

## 5. Access Modifiers: `public`, `protected`, `private` vs ECMAScript `#private`

TypeScript provides two different encapsulation models:

| Access Modifier | Keyword | Enforcement Stage | Runtime Behavior |
| :--- | :--- | :--- | :--- |
| **Public** | `public` (default) | Compile-time | Accessible everywhere |
| **Protected** | `protected` | Compile-time | Accessible within class and subclasses |
| **TypeScript Private** | `private` | **Compile-time only** | Soft privacy (can be accessed via `(obj as any).field`) |
| **ECMAScript Private** | `#fieldName` | **Runtime (V8 engine)** | **Hard privacy** (Throws SyntaxError if accessed outside class) |

```typescript
export class BankAccount extends BaseEntity {
  // TypeScript private: soft privacy at compile time
  private _balance: number;

  // ECMAScript hard private field: truly inaccessible outside this class even at runtime
  #encryptionKey: string;

  // Static member: belongs to the class constructor, not instances
  public static readonly CURRENCY = "USD";

  // Static initialization block (ES2022)
  static {
    console.log(`[BankAccount] Initialized class for currency: ${BankAccount.CURRENCY}`);
  }

  constructor(
    id: string,
    public readonly ownerName: string,
    initialDeposit: number,
    secretKey: string
  ) {
    super(id);
    this._balance = initialDeposit;
    this.#encryptionKey = secretKey;
  }

  // Getter & Setter
  public get balance(): number {
    return this._balance;
  }

  // Setters must have compatible parameter types with getters
  public set balance(amount: number) {
    if (amount < 0) throw new Error("Balance cannot be negative");
    this._balance = amount;
    this.touch();
  }

  // Implementation of abstract method with 'override' check
  public override validate(): boolean {
    return this._balance >= 0 && this.ownerName.length > 0;
  }

  public deposit(amount: number): void {
    if (amount <= 0) throw new Error("Deposit amount must be positive");
    this._balance += amount;
    this.touch();
  }

  public withdraw(amount: number): boolean {
    if (amount > this._balance) {
      return false; // Insufficient funds
    }
    this._balance -= amount;
    this.touch();
    return true;
  }
}
```

---

## 6. The `override` Keyword (`noImplicitOverride: true`)

When overriding a method in a subclass, the `override` keyword ensures that:

1. The method actually exists on the parent class (protects against misspelled method names).
2. If the base class method is renamed or removed in the future, the compiler alerts you immediately.

```typescript
class BaseService {
  public executeTask(): void {
    console.log("Executing base task");
  }
}

class CustomService extends BaseService {
  // ✅ Valid: explicitly marks override
  public override executeTask(): void {
    super.executeTask();
    console.log("Adding custom telemetry");
  }

  // ❌ Error: This member cannot have an 'override' modifier because it is not declared in the base class 'BaseService'.
  // public override executeNonExistent(): void {}
}
```

---

## 7. Generic Classes & Repository Pattern

```typescript
export interface Repository<T extends BaseEntity> {
  findById(id: string): Promise<T | null>;
  save(entity: T): Promise<void>;
  delete(id: string): Promise<boolean>;
}

export class InMemoryRepository<T extends BaseEntity> implements Repository<T> {
  protected items = new Map<string, T>();

  async findById(id: string): Promise<T | null> {
    const item = this.items.get(id);
    return item ? (JSON.parse(JSON.stringify(item)) as T) : null;
  }

  async save(entity: T): Promise<void> {
    if (!entity.validate()) {
      throw new Error(`Entity ${entity.id} failed validation`);
    }
    this.items.set(entity.id, entity);
  }

  async delete(id: string): Promise<boolean> {
    return this.items.delete(id);
  }

  async count(): Promise<number> {
    return this.items.size;
  }
}

// Usage:
const accountRepo = new InMemoryRepository<BankAccount>();
const account = new BankAccount("acc_1", "Alice", 500, "sec_123");
await accountRepo.save(account);
```

---

## Troubleshooting & Best Practices

1. **Avoid Overusing Classes for Simple Data DTOs**
   In TypeScript, prefer plain objects and `type` / `interface` definitions for data packets and API payloads. Use classes when you need true behavior encapsulation, private invariants, or polymorphism.

2. **Function Overload Implementation Visibility**
   Remember that the implementation signature of an overloaded function is **internal**. Callers only see the overload signatures above it. If an argument combination is not listed in an overload, callers cannot invoke it even if the implementation signature accepts it.

3. **Prefer `#private` for Security-Sensitive Invariants**
   `private` in TypeScript is purely a compile-time check. If an untrusted script or dynamic library runs in your Node process, it can still access `(instance as any)._privateField`. Use `#privateField` when runtime isolation is mandatory.
