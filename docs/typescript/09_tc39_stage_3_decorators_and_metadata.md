# Module 09: TC39 Stage 3 Decorators & Metadata Architecture

**Track:** TypeScript — Enterprise Type System
**Category:** Metaprogramming & Modern Decorator Standards

---

## 1. The Evolution of Decorators: Legacy vs Standard TC39

For years, TypeScript supported an early, experimental decorator proposal enabled via `"experimentalDecorators": true` and `"emitDecoratorMetadata": true` (used heavily by Angular and NestJS).

In **TypeScript 5.0**, TypeScript officially implemented the **standardized TC39 Stage 3 Decorator specification**.

| Feature | Legacy Decorators (`experimentalDecorators: true`) | Standard TC39 Decorators (TS 5.0+) |
| :--- | :--- | :--- |
| **Standard Status** | Obsolete Stage 1 Draft (2014) | **Official TC39 Stage 3 Standard** (2023+) |
| **Configuration** | Requires `"experimentalDecorators": true` | **Zero config required** (`"experimentalDecorators": false`) |
| **Context Argument** | Implicit `propertyKey`, `descriptor` arguments | **Explicit `context` object** with strict typing and metadata |
| **Field Decoration** | Cannot replace field initializer values | **Supported** via initializer return functions |
| **Auto-Accessors** | Not supported | **Supported** via `accessor` keyword |
| **Runtime Portability** | TypeScript-only | Works across modern JS runtimes natively |

---

## 2. The TC39 Decorator Execution Model & Context

A TC39 decorator is a function that accepts two arguments:

1. `value`: The target being decorated (class constructor, method function, getter, setter, or accessor).
2. `context`: An object containing metadata about the decorated entity.

```typescript
type ClassMethodDecorator = (
  target: Function,
  context: ClassMethodDecoratorContext
) => Function | void;
```

### The `ClassMethodDecoratorContext` Object Structure

```typescript
interface ClassMethodDecoratorContext {
  kind: "method";
  name: string | symbol;
  static: boolean;
  private: boolean;
  access: {
    has(object: unknown): boolean;
    get(object: unknown): unknown;
  };
  addInitializer(initializer: () => void): void;
  metadata?: Record<string | symbol, unknown>;
}
```

---

## 3. Practical TC39 Decorators

### 1. Method Decorator: Execution Logging & Performance Profiler (`@Logged`)

```typescript
export function Logged<This, Args extends any[], Return>(
  target: (this: This, ...args: Args) => Return,
  context: ClassMethodDecoratorContext<This, (this: This, ...args: Args) => Return>
) {
  const methodName = String(context.name);

  // Return a replacement wrapper function
  return function (this: This, ...args: Args): Return {
    const startTime = performance.now();
    console.log(`[EXEC START]: ${methodName} with arguments:`, args);

    try {
      const result = target.apply(this, args);

      // Handle async promise returns transparently
      if (result instanceof Promise) {
        return result.then((res) => {
          const duration = (performance.now() - startTime).toFixed(2);
          console.log(`[EXEC SUCCESS]: ${methodName} resolved in ${duration}ms`);
          return res;
        }) as Return;
      }

      const duration = (performance.now() - startTime).toFixed(2);
      console.log(`[EXEC SUCCESS]: ${methodName} completed in ${duration}ms`);
      return result;
    } catch (error) {
      console.error(`[EXEC FAILED]: ${methodName} threw error:`, error);
      throw error;
    }
  };
}
```

### 2. Method Decorator Factory: `@Debounce(ms)`

When a decorator requires custom parameters, wrap it in a **Decorator Factory**:

```typescript
export function Debounce(delayMs: number) {
  return function <This, Args extends any[], Return>(
    target: (this: This, ...args: Args) => Return,
    context: ClassMethodDecoratorContext<This, (this: This, ...args: Args) => Return>
  ) {
    return function (this: This, ...args: Args) {
      // Store timer on instance to prevent cross-instance collision
      const timerKey = Symbol.for(`__debounce_${String(context.name)}`);
      const self = this as any;

      if (self[timerKey]) {
        clearTimeout(self[timerKey]);
      }

      self[timerKey] = setTimeout(() => {
        target.apply(this, args);
        delete self[timerKey];
      }, delayMs);
    };
  };
}
```

---

## 4. Auto-Accessor Decorators (`accessor`)

TC39 introduced the **`accessor`** keyword for class fields. An auto-accessor automatically generates a private backing field with getter and setter pairs:

```typescript
class Product {
  // Generates getter/setter automatically:
  accessor price: number = 100;
}
```

### Practical Auto-Accessor Decorator: `@Min(limit)` Validation

```typescript
export function Min(limit: number) {
  return function <This, Value extends number>(
    target: ClassAccessorDecoratorTarget<This, Value>,
    context: ClassAccessorDecoratorContext<This, Value>
  ): ClassAccessorDecoratorResult<This, Value> {
    return {
      get(this: This): Value {
        return target.get.call(this);
      },
      set(this: This, value: Value) {
        if (value < limit) {
          throw new Error(
            `Validation Error on ${String(context.name)}: Value ${value} must be >= ${limit}`
          );
        }
        target.set.call(this, value);
      },
      init(initialValue: Value): Value {
        if (initialValue < limit) {
          throw new Error(`Initial value for ${String(context.name)} must be >= ${limit}`);
        }
        return initialValue;
      },
    };
  };
}
```

---

## 5. Class Decorator: Singleton Enforcement

Class decorators can wrap or replace the entire class constructor:

```typescript
export function Singleton<T extends abstract new (...args: any[]) => any>(
  target: T,
  context: ClassDecoratorContext<T>
) {
  let instance: InstanceType<T> | null = null;

  return class extends target {
    constructor(...args: any[]) {
      if (instance) {
        return instance;
      }
      super(...args);
      instance = this as InstanceType<T>;
    }
  };
}
```

---

## 6. Consuming TC39 Decorators in an Enterprise Service

```typescript
@Singleton
export class PaymentProcessingService {
  @Min(0)
  accessor currentDailyVolume: number = 0;

  @Logged
  public async executeCharge(customerId: string, amount: number): Promise<string> {
    // Simulate transaction
    await new Promise((resolve) => setTimeout(resolve, 150));
    this.currentDailyVolume += amount;
    return `tx_${Date.now()}`;
  }

  @Debounce(500)
  public syncTelemetryWithDataLake(): void {
    console.log(`[Telemetry] Broadcasting daily volume: $${this.currentDailyVolume}`);
  }
}

// Verification:
const service1 = new PaymentProcessingService();
const service2 = new PaymentProcessingService();
console.log(service1 === service2); // true (Singleton verified!)

await service1.executeCharge("cust_123", 250);
service1.syncTelemetryWithDataLake();
```

---

## Troubleshooting & Best Practices

1. **Do not mix `experimentalDecorators` with TC39 Stage 3 syntax**
   Ensure `"experimentalDecorators": false` is set in `tsconfig.json` when using modern Stage 3 decorators.

2. **Decorators execute at class definition time**
   Decorators run **once** when the class module is loaded into memory by the JavaScript runtime, not when class instances are created. Initializers registered via `context.addInitializer` run when instances are instantiated.
