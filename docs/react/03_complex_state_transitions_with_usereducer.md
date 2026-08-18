# Module 03: Complex State Transitions with `useReducer` & State Machines

**Track:** React — Modern UI & Fiber Architecture  
**Category:** State Architecture, Reducer Pipelines & Finite State Machines

---

## 1. When to Use `useReducer` vs `useState`

While `useState` is ideal for simple independent primitives (booleans, strings, single IDs), as component state grows in complexity, multiple `useState` calls create synchronization bugs:

| Scenario | `useState` | `useReducer` |
| :--- | :--- | :--- |
| **State Shape** | Simple primitives / independent variables | **Complex objects, nested arrays, interdependent fields** |
| **State Transitions** | Direct setter assignments (`setA(1); setB(2);`) | **Declarative action dispatches** (`dispatch({ type: 'CHECKOUT' })`) |
| **Next State Logic** | Spread across multiple event handlers | **Centralized in a single pure reducer function** |
| **Testing** | Requires component mounting / rendering | **Reducer function is pure JS and easily unit tested** |
| **State Machine Modeling** | Prone to illegal transition states | **Guarantees valid state machine transitions** |

---

## 2. Anatomy of the Reducer Pattern

A **Reducer** is a pure function that takes the current `state` and an `action` object, and calculates the `nextState`:

$$(\text{State}, \text{Action}) \implies \text{NextState}$$

```tsx
const [state, dispatch] = useReducer(reducer, initialArg, init?);
```

---

## 3. Building a Type-Safe Reducer with Discriminated Unions

Let's model a shopping cart with complex actions (adding items, updating quantities, applying discount codes, clearing):

```tsx
// src/reducers/cartReducer.ts

export interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

export interface CartState {
  items: CartItem[];
  discountCode: string | null;
  discountPercentage: number;
}

// Discriminated Union of Actions
export type CartAction =
  | { type: "ADD_ITEM"; payload: { id: string; name: string; price: number } }
  | { type: "REMOVE_ITEM"; payload: { id: string } }
  | { type: "UPDATE_QUANTITY"; payload: { id: string; quantity: number } }
  | { type: "APPLY_DISCOUNT"; payload: { code: string } }
  | { type: "CLEAR_CART" };

export const initialCartState: CartState = {
  items: [],
  discountCode: null,
  discountPercentage: 0,
};

export function cartReducer(state: CartState, action: CartAction): CartState {
  switch (action.type) {
    case "ADD_ITEM": {
      const existingIndex = state.items.findIndex((item) => item.id === action.payload.id);
      if (existingIndex !== -1) {
        // Item exists: increase quantity
        const updatedItems = state.items.map((item, idx) =>
          idx === existingIndex ? { ...item, quantity: item.quantity + 1 } : item
        );
        return { ...state, items: updatedItems };
      }
      // New item: append to items array
      return {
        ...state,
        items: [...state.items, { ...action.payload, quantity: 1 }],
      };
    }

    case "REMOVE_ITEM":
      return {
        ...state,
        items: state.items.filter((item) => item.id !== action.payload.id),
      };

    case "UPDATE_QUANTITY": {
      const { id, quantity } = action.payload;
      if (quantity <= 0) {
        return {
          ...state,
          items: state.items.filter((item) => item.id !== id),
        };
      }
      return {
        ...state,
        items: state.items.map((item) =>
          item.id === id ? { ...item, quantity } : item
        ),
      };
    }

    case "APPLY_DISCOUNT": {
      const code = action.payload.code.trim().toUpperCase();
      let discountPercentage = 0;
      if (code === "SAVE20") discountPercentage = 0.20;
      if (code === "VIP50") discountPercentage = 0.50;

      return {
        ...state,
        discountCode: discountPercentage > 0 ? code : null,
        discountPercentage,
      };
    }

    case "CLEAR_CART":
      return initialCartState;

    default:
      return state;
  }
}
```

---

## 4. Modeling Finite State Machines (FSM)

A **Finite State Machine** guarantees that your application can only be in one of a finite set of known states, and transitions between states are strictly controlled.

```tsx
// Modeling an Async Network Fetch State Machine:
export type FetchState<T> =
  | { status: "idle"; data: null; error: null }
  | { status: "loading"; data: T | null; error: null }
  | { status: "success"; data: T; error: null }
  | { status: "error"; data: T | null; error: Error };

export type FetchAction<T> =
  | { type: "FETCH_START" }
  | { type: "FETCH_SUCCESS"; payload: T }
  | { type: "FETCH_ERROR"; payload: Error }
  | { type: "RESET" };

export function createFetchReducer<T>() {
  return function fetchReducer(
    state: FetchState<T>,
    action: FetchAction<T>
  ): FetchState<T> {
    switch (action.type) {
      case "FETCH_START":
        return { status: "loading", data: state.data, error: null };
      case "FETCH_SUCCESS":
        return { status: "success", data: action.payload, error: null };
      case "FETCH_ERROR":
        return { status: "error", data: state.data, error: action.payload };
      case "RESET":
        return { status: "idle", data: null, error: null };
      default:
        return state;
    }
  };
}
```

---

## 5. Consuming `useReducer` in Components

```tsx
import { useReducer, useMemo } from "react";
import { cartReducer, initialCartState } from "./cartReducer";

export function ShoppingCartView() {
  const [state, dispatch] = useReducer(cartReducer, initialCartState);

  // Derived state calculated purely during render:
  const subtotal = useMemo(() => {
    return state.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  }, [state.items]);

  const total = useMemo(() => {
    return subtotal * (1 - state.discountPercentage);
  }, [subtotal, state.discountPercentage]);

  return (
    <div className="cart-container">
      <h2>Your Shopping Cart</h2>

      <div className="cart-items">
        {state.items.map((item) => (
          <div key={item.id} className="cart-row">
            <span>{item.name} (${item.price})</span>
            <button onClick={() => dispatch({ type: "UPDATE_QUANTITY", payload: { id: item.id, quantity: item.quantity - 1 } })}>-</button>
            <span>{item.quantity}</span>
            <button onClick={() => dispatch({ type: "UPDATE_QUANTITY", payload: { id: item.id, quantity: item.quantity + 1 } })}>+</button>
            <button onClick={() => dispatch({ type: "REMOVE_ITEM", payload: { id: item.id } })}>Remove</button>
          </div>
        ))}
      </div>

      <div className="discount-section">
        <input
          placeholder="Promo code"
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              dispatch({ type: "APPLY_DISCOUNT", payload: { code: e.currentTarget.value } });
            }
          }}
        />
        {state.discountCode && <p>Applied code: {state.discountCode} (-{state.discountPercentage * 100}%)</p>}
      </div>

      <div className="totals">
        <p>Subtotal: ${subtotal.toFixed(2)}</p>
        <h3>Total: ${total.toFixed(2)}</h3>
        <button onClick={() => dispatch({ type: "CLEAR_CART" })}>Clear Cart</button>
      </div>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Keep Reducers 100% Pure**
   Reducers must never perform side effects (no `fetch()`, no `localStorage.setItem()`, no generating `Math.random()` or `Date.now()`). Pass generated timestamps and UUIDs inside the `action.payload`.

2. **Always Return New State References for Updates**
   Mutating `state.items.push()` inside a reducer will cause React to skip re-renders because `newState === oldState`. Always use object and array spreads.