# Module 15: Design Patterns in TypeScript — Gang of Four (GoF) & Modern Idioms

**Track:** TypeScript — Enterprise Type System  
**Category:** Software Architecture & Design Patterns

---

## 1. Classical GoF Patterns in Modern TypeScript

The original 23 Gang of Four (GoF) design patterns were formulated in the context of classical, nominal object-oriented languages (C++, Smalltalk). In TypeScript, the combination of **first-class functions, structural typing, generics, and object literals** allows implementing these patterns with significantly less boilerplate and greater type safety.

---

## 2. Creational Patterns

### 1. Step-Safe Builder Pattern (Phantom Type State Machine)

A traditional Builder allows calling `.build()` prematurely before mandatory fields are populated. In TypeScript, we can use **Phantom Types** to construct a compile-time state machine where `.build()` is **physically impossible to call until all mandatory fields are provided**:

```typescript
interface RequestPayload {
  url: string;
  method: "GET" | "POST";
  headers: Record<string, string>;
  body?: string;
}

// Phantom state markers
type HasNoUrl = { readonly __hasUrl: false };
type HasUrl = { readonly __hasUrl: true };
type HasNoMethod = { readonly __hasMethod: false };
type HasMethod = { readonly __hasMethod: true };

export class SafeRequestBuilder<TUrlState = HasNoUrl, TMethodState = HasNoMethod> {
  private urlValue?: string;
  private methodValue?: "GET" | "POST";
  private headersValue: Record<string, string> = {};
  private bodyValue?: string;

  private constructor() {}

  public static create(): SafeRequestBuilder<HasNoNoUrl, HasNoMethod> {
    return new SafeRequestBuilder<HasNoUrl, HasNoMethod>();
  }

  public url(targetUrl: string): SafeRequestBuilder<HasUrl, TMethodState> {
    const next = this as any as SafeRequestBuilder<HasUrl, TMethodState>;
    next.urlValue = targetUrl;
    return next;
  }

  public method(targetMethod: "GET" | "POST"): SafeRequestBuilder<TUrlState, HasMethod> {
    const next = this as any as SafeRequestBuilder<TUrlState, HasMethod>;
    next.methodValue = targetMethod;
    return next;
  }

  public header(key: string, value: string): this {
    this.headersValue[key] = value;
    return this;
  }

  public body(data: string): this {
    this.bodyValue = data;
    return this;
  }

  // .build() is ONLY available when TUrlState === HasUrl AND TMethodState === HasMethod!
  public build(
    this: SafeRequestBuilder<HasUrl, HasMethod>
  ): RequestPayload {
    return {
      url: this.urlValue!,
      method: this.methodValue!,
      headers: this.headersValue,
      body: this.bodyValue,
    };
  }
}

// Consuming the Step-Safe Builder:
const validRequest = SafeRequestBuilder.create()
  .url("https://api.example.com/data")
  .method("POST")
  .header("Authorization", "Bearer token_123")
  .body(JSON.stringify({ active: true }))
  .build(); // ✅ Compiles cleanly!

// ❌ Compile Error: Missing .method() before .build()!
// SafeRequestBuilder.create()
//   .url("https://api.example.com/data")
//   .build(); // Error: The 'this' context of type 'SafeRequestBuilder<HasUrl, HasNoMethod>' is not assignable to method's 'this' of type 'SafeRequestBuilder<HasUrl, HasMethod>'.
```

### 2. Abstract Factory Pattern

```typescript
export interface CloudStorageClient {
  uploadFile(path: string, content: Buffer): Promise<string>;
  deleteFile(path: string): Promise<boolean>;
}

export interface CloudQueueClient {
  publishMessage(queueName: string, message: unknown): Promise<void>;
}

export interface CloudProviderFactory {
  createStorage(): CloudStorageClient;
  createQueue(): CloudQueueClient;
}

// AWS Implementation
export class AwsProviderFactory implements CloudProviderFactory {
  createStorage(): CloudStorageClient {
    return {
      uploadFile: async (path, content) => `https://s3.amazonaws.com/bucket/${path}`,
      deleteFile: async () => true,
    };
  }
  createQueue(): CloudQueueClient {
    return {
      publishMessage: async (queue, msg) => console.log(`[AWS SQS] Enqueued to ${queue}`, msg),
    };
  }
}

// GCP Implementation
export class GcpProviderFactory implements CloudProviderFactory {
  createStorage(): CloudStorageClient {
    return {
      uploadFile: async (path, content) => `https://storage.googleapis.com/bucket/${path}`,
      deleteFile: async () => true,
    };
  }
  createQueue(): CloudQueueClient {
    return {
      publishMessage: async (queue, msg) => console.log(`[GCP PubSub] Enqueued to ${queue}`, msg),
    };
  }
}
```

---

## 3. Structural Patterns

### 1. Adapter Pattern (Standardizing Third-Party SDKs)

```typescript
// Target Interface expected by internal domain
export interface PaymentProcessor {
  processPayment(cents: number, customerToken: string): Promise<{ transactionId: string; success: boolean }>;
}

// Legacy / Third-Party Incompatible SDK
class LegacyStripeSDK {
  chargeCard(amountInDollars: number, customerId: string, currency: string) {
    return { id: `ch_${Date.now()}`, status: "paid" };
  }
}

// Adapter
export class StripePaymentAdapter implements PaymentProcessor {
  constructor(private stripeSDK: LegacyStripeSDK) {}

  async processPayment(cents: number, customerToken: string) {
    const dollars = cents / 100;
    const response = this.stripeSDK.chargeCard(dollars, customerToken, "USD");
    return {
      transactionId: response.id,
      success: response.status === "paid",
    };
  }
}
```

### 2. Proxy Pattern (Lazy Loading & Access Control)

```typescript
export interface DataWarehouse {
  fetchQuarterlyReport(quarter: string): Promise<string[]>;
}

export class RealDataWarehouse implements DataWarehouse {
  constructor() {
    console.log("[RealDataWarehouse] Initializing heavy database connection pool...");
  }
  async fetchQuarterlyReport(quarter: string): Promise<string[]> {
    return [`Revenue Report for ${quarter}`, "EBITDA: $4.2M"];
  }
}

// Lazy Proxy: Delays instantiation until the first query is actually executed
export class LazyDataWarehouseProxy implements DataWarehouse {
  private instance: RealDataWarehouse | null = null;

  async fetchQuarterlyReport(quarter: string): Promise<string[]> {
    if (!this.instance) {
      this.instance = new RealDataWarehouse();
    }
    return this.instance.fetchQuarterlyReport(quarter);
  }
}
```

---

## 4. Behavioral Patterns

### 1. Strategy Pattern (Interchangeable Pricing Algorithms)

```typescript
export interface PricingStrategy {
  calculatePrice(basePrice: number, quantity: number): number;
}

export class StandardPricingStrategy implements PricingStrategy {
  calculatePrice(basePrice: number, quantity: number): number {
    return basePrice * quantity;
  }
}

export class VolumeDiscountStrategy implements PricingStrategy {
  calculatePrice(basePrice: number, quantity: number): number {
    const rawTotal = basePrice * quantity;
    if (quantity >= 50) return rawTotal * 0.8; // 20% discount
    if (quantity >= 10) return rawTotal * 0.9; // 10% discount
    return rawTotal;
  }
}

export class BlackFridayPricingStrategy implements PricingStrategy {
  calculatePrice(basePrice: number, quantity: number): number {
    return (basePrice * 0.5) * quantity; // 50% off
  }
}

// Context: Shopping Cart Checkout
export class CheckoutOrder {
  constructor(
    public readonly baseItemPrice: number,
    public readonly quantity: number,
    private pricingStrategy: PricingStrategy = new StandardPricingStrategy()
  ) {}

  public setPricingStrategy(strategy: PricingStrategy): void {
    this.pricingStrategy = strategy;
  }

  public getTotal(): number {
    return this.pricingStrategy.calculatePrice(this.baseItemPrice, this.quantity);
  }
}
```

### 2. Command Pattern (Undo/Redo History Queue)

```typescript
export interface Command {
  execute(): void;
  undo(): void;
}

export class CanvasEditor {
  private shapes: string[] = [];

  addShape(shape: string) {
    this.shapes.push(shape);
    console.log("Canvas:", this.shapes);
  }

  removeShape(shape: string) {
    this.shapes = this.shapes.filter((s) => s !== shape);
    console.log("Canvas:", this.shapes);
  }
}

export class AddShapeCommand implements Command {
  constructor(private editor: CanvasEditor, private shape: string) {}

  execute(): void {
    this.editor.addShape(this.shape);
  }

  undo(): void {
    this.editor.removeShape(this.shape);
  }
}

export class CommandHistoryManager {
  private history: Command[] = [];
  private undone: Command[] = [];

  public execute(command: Command): void {
    command.execute();
    this.history.push(command);
    this.undone = []; // Reset redo stack
  }

  public undo(): void {
    const cmd = this.history.pop();
    if (cmd) {
      cmd.undo();
      this.undone.push(cmd);
    }
  }

  public redo(): void {
    const cmd = this.undone.pop();
    if (cmd) {
      cmd.execute();
      this.history.push(cmd);
    }
  }
}
```

---

## Troubleshooting & Best Practices

1. **Favor Composition over Class Inheritance**
   Deep class inheritance trees (`class E extends D extends C extends B extends A`) become brittle and hard to refactor. Use Strategy, Adapter, and Factory patterns with interfaces.

2. **Prefer Object Literals for Simple Strategies**
   If a strategy has no internal state, a dictionary of pure functions `Record<StrategyType, (args) => Result>` is simpler and more idiomatic than creating 5 separate classes.
