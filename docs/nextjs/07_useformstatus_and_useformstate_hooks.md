# Module 07: Form Hooks & Progressive Enhancement — `useActionState` & `useFormStatus`

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Form Handling, Accessibility & Progressive Enhancement

---

## 1. The Full-Stack Form Architecture in Next.js

In traditional Single Page Applications, forms rely entirely on JavaScript client-side event handlers (`e.preventDefault()`, `fetch()`). If client JavaScript fails to load, crashes, or is blocked by browser extensions, the entire form is unusable.

Next.js App Router and React 19 embrace **Progressive Enhancement**:

1. **Without JavaScript (Baseline)**: Standard HTML `<form method="POST" action="/action">` submits via standard HTTP POST to the server, mutations execute, and the page reloads with fresh state.
2. **With JavaScript (Enhanced)**: React intercepts the form submission, sends a background fetch request, displays instant loading indicators via `useFormStatus`, updates errors via `useActionState`, and preserves scroll position without a full page reload!

---

## 2. `useActionState` (Managing Server Action State & Errors)

`useActionState` manages the state returned by a Server Action across submissions:

```typescript
const [state, formAction, isPending] = useActionState(serverAction, initialState);
```

```tsx
// src/components/FeedbackForm.tsx
"use client";

import { useActionState } from "react";
import { submitFeedbackAction, type FeedbackState } from "@/actions/feedbackActions";
import { SubmitButton } from "./SubmitButton";

const initialFeedbackState: FeedbackState = {
  success: false,
  message: "",
  errors: {},
};

export function FeedbackForm() {
  const [state, formAction, isPending] = useActionState(
    submitFeedbackAction,
    initialFeedbackState
  );

  return (
    <div className="form-card">
      <h2>Send Feedback</h2>

      {state.success ? (
        <div className="alert-success">
          <p>{state.message || "Thank you for your feedback!"}</p>
        </div>
      ) : (
        <form action={formAction} className="space-y-4">
          <div>
            <label htmlFor="email">Your Email</label>
            <input
              id="email"
              name="email"
              type="email"
              disabled={isPending}
              required
            />
            {state.errors?.email && (
              <span className="error-text">{state.errors.email[0]}</span>
            )}
          </div>

          <div>
            <label htmlFor="rating">Rating (1 to 5)</label>
            <select id="rating" name="rating" disabled={isPending} defaultValue="5">
              <option value="5">⭐⭐⭐⭐⭐ Excellent</option>
              <option value="4">⭐⭐⭐⭐ Good</option>
              <option value="3">⭐⭐⭐ Average</option>
              <option value="2">⭐⭐ Poor</option>
              <option value="1">⭐ Terrible</option>
            </select>
          </div>

          <div>
            <label htmlFor="comments">Comments</label>
            <textarea
              id="comments"
              name="comments"
              rows={4}
              disabled={isPending}
              placeholder="Tell us how we can improve..."
            />
            {state.errors?.comments && (
              <span className="error-text">{state.errors.comments[0]}</span>
            )}
          </div>

          <SubmitButton label="Submit Feedback" />
        </form>
      )}
    </div>
  );
}
```

---

## 3. `useFormStatus` (Decoupled Child Submit Controls)

`useFormStatus` allows any child component inside a `<form>` to know whether the parent form is currently being submitted:

```tsx
// src/components/SubmitButton.tsx
"use client";

import { useFormStatus } from "react-dom";

export function SubmitButton({
  label = "Submit",
  pendingLabel = "Submitting...",
}: {
  label?: string;
  pendingLabel?: string;
}) {
  // Automatically reads parent form state:
  const { pending, data, method, action } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending}
      className={`btn-primary ${pending ? "btn-primary--loading" : ""}`}
    >
      {pending ? (
        <span className="flex items-center gap-2">
          <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
          </svg>
          {pendingLabel}
        </span>
      ) : (
        label
      )}
    </button>
  );
}
```

*Crucial Architecture Note:* `useFormStatus` **must be called from a component rendered inside the `<form>`**. It will not read status if called in the same component that renders the `<form>` tag itself.

---

## 4. The Server Action Definition

```typescript
// src/app/actions/feedbackActions.ts
"use server";

import { z } from "zod";

const FeedbackSchema = z.object({
  email: z.string().email("Invalid email format"),
  rating: z.coerce.number().min(1).max(5),
  comments: z.string().min(5, "Comments must be at least 5 characters"),
});

export interface FeedbackState {
  success: boolean;
  message?: string;
  errors?: Record<string, string[]>;
}

export async function submitFeedbackAction(
  prevState: FeedbackState,
  formData: FormData
): Promise<FeedbackState> {
  const rawData = {
    email: formData.get("email"),
    rating: formData.get("rating"),
    comments: formData.get("comments"),
  };

  const validation = FeedbackSchema.safeParse(rawData);
  if (!validation.success) {
    return {
      success: false,
      errors: validation.error.flatten().fieldErrors,
    };
  }

  // Simulate storing feedback in database
  await new Promise((resolve) => setTimeout(resolve, 800));

  return {
    success: true,
    message: "Feedback received successfully. Thank you!",
  };
}
```

---

## Troubleshooting & Best Practices

1. **`useFormState` vs `useActionState`**
   `useFormState` from `react-dom` was renamed to `useActionState` (imported from `react`) in React 19 and Next.js 15. Always import `useActionState` from `"react"`.

2. **Form Resetting on Success**
   When `useActionState` returns `success: true`, you can reset the form using an uncontrolled `<form>` with a `key` prop tied to submission count, or call `formRef.current.reset()` in an effect.
