# Module 18: Component Testing — React Testing Library, Vitest & MSW

**Track:** React — Modern UI & Fiber Architecture
**Category:** Automated Testing, Accessibility Queries & Network Mocking

---

## 1. The React Testing Library (RTL) Philosophy

Historically, tools like Enzyme tested component implementation details (inspecting internal `state`, private methods, or shallow child tree properties). When developers refactored a component (e.g. converting `useState` to `useReducer`), all unit tests broke even though the UI behaved identically for the user.

**React Testing Library (RTL)** enforces testing **behavior from the user's perspective**:

> *"The more your tests resemble the way your software is used, the more confidence they can give you."* — Kent C. Dodds

```text
Implementation Testing (Enzyme / Fragile):
expect(wrapper.state('count')).toBe(1);  ◄── Breaks on refactor

User-Centric Testing (React Testing Library / Resilient):
await userEvent.click(screen.getByRole('button', { name: /increment/i }));
expect(screen.getByText(/count: 1/i)).toBeInTheDocument();
```

---

## 2. Setting Up Vitest & React Testing Library

```bash
npm install -D vitest @testing-library/react @testing-library/user-event @testing-library/jest-dom happy-dom msw
```

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: "happy-dom",
    setupFiles: ["./test/setup.ts"],
  },
});
```

```typescript
// test/setup.ts
import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// Clean up DOM after each test
afterEach(() => {
  cleanup();
});
```

---

## 3. RTL Query Priority Cheat Sheet

Always use the highest priority query that applies:

1. **`getByRole` / `findByRole`**: Queries by accessible ARIA role (`button`, `heading`, `textbox`, `checkbox`, `dialog`). **Preferred 90% of the time.**
2. **`getByLabelText`**: Queries form inputs linked to `<label>` elements.
3. **`getByPlaceholderText`**: Queries inputs by placeholder text.
4. **`getByText`**: Queries non-interactive text content (paragraphs, spans).
5. **`getByTestId`**: Last resort for non-standard elements (`data-testid="custom-widget"`).

| Query Variant | No Match | 1 Match | 1+ Matches | Async (Awaits DOM) |
| :--- | :--- | :--- | :--- | :--- |
| **`getBy...`** | **Throws Error** | Returns Element | Throws Error | No |
| **`queryBy...`** | **Returns `null`** (Use to assert element is NOT present) | Returns Element | Throws Error | No |
| **`findBy...`** | **Throws Error** (after timeout) | Returns Element | Throws Error | **Yes (Promise)** |

---

## 4. Comprehensive Component Test Suite with `userEvent`

Let's test an interactive login form:

```tsx
// src/components/LoginForm.tsx
import { useState } from "react";

export function LoginForm({ onLogin }: { onLogin: (email: string) => Promise<void> }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!email || !password) {
      setError("All fields are required");
      return;
    }

    setIsSubmitting(true);
    setError(null);
    try {
      await onLogin(email);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} aria-label="Login Form">
      {error && <div role="alert" className="error">{error}</div>}

      <div>
        <label htmlFor="email">Email Address</label>
        <input
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </div>

      <div>
        <label htmlFor="password">Password</label>
        <input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? "Authenticating..." : "Sign In"}
      </button>
    </form>
  );
}
```

```typescript
// test/components/LoginForm.spec.tsx
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LoginForm } from "@/components/LoginForm";

describe("LoginForm Component", () => {
  it("renders form controls with accessible labels", () => {
    render(<LoginForm onLogin={vi.fn()} />);

    expect(screen.getByRole("form", { name: /login form/i })).toBeInTheDocument();
    expect(screen.getByLabelText(/email address/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /sign in/i })).toBeInTheDocument();
  });

  it("displays validation error when submitted empty", async () => {
    const user = userEvent.setup();
    render(<LoginForm onLogin={vi.fn()} />);

    await user.click(screen.getByRole("button", { name: /sign in/i }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(/all fields are required/i);
  });

  it("calls onLogin with input values on valid submission", async () => {
    const user = userEvent.setup();
    const handleLoginMock = vi.fn().mockResolvedValue(undefined);

    render(<LoginForm onLogin={handleLoginMock} />);

    // Simulate real keyboard typing:
    await user.type(screen.getByLabelText(/email address/i), "alice@example.com");
    await user.type(screen.getByLabelText(/password/i), "SecureP@ss123");

    // Click submit button:
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(handleLoginMock).toHaveBeenCalledTimes(1);
    expect(handleLoginMock).toHaveBeenCalledWith("alice@example.com");
  });
});
```

---

## 5. Mocking Network Requests with Mock Service Worker (MSW)

Instead of mocking `fetch` manually, **MSW (Mock Service Worker)** intercepts real network requests at the HTTP layer:

```typescript
// test/mocks/handlers.ts
import { http, HttpResponse } from "msw";

export const handlers = [
  http.get("https://api.example.com/v1/user", () => {
    return HttpResponse.json({
      id: "u_123",
      name: "Alice Chen",
      email: "alice@example.com",
    });
  }),
];
```

```typescript
// test/mocks/server.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";

export const server = setupServer(...handlers);
```

---

## 6. Testing Custom Hooks with `renderHook`

```typescript
// test/hooks/useCounter.spec.ts
import { describe, it, expect } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useCounter } from "@/hooks/useCounter";

describe("useCounter Hook", () => {
  it("initializes with default value and increments state", () => {
    const { result } = renderHook(() => useCounter(10));

    expect(result.current.count).toBe(10);

    // State mutations must be wrapped in act():
    act(() => {
      result.current.increment();
    });

    expect(result.current.count).toBe(11);
  });
});
```

---

## Troubleshooting & Best Practices

1. **`act(...)` Warnings**
   If you encounter `Warning: An update to Component inside a test was not wrapped in act(...)`, it means an asynchronous state update resolved *after* your test completed. Use `await screen.findByRole(...)` or `await waitFor(...)` to await the DOM resolution.

2. **Prefer `userEvent` over `fireEvent`**
   `fireEvent.click()` simply dispatches a single raw DOM event. `userEvent.click()` simulates full user interaction behavior (hovering, focusing, pressing down, releasing, and firing click events).
