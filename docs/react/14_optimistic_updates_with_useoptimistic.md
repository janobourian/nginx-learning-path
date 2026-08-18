# Module 14: Optimistic UI Updates with `useOptimistic`

**Track:** React — Modern UI & Fiber Architecture  
**Category:** Asynchronous UX, Optimistic UI & React 19 Standards

---

## 1. What Are Optimistic Updates?

In traditional web applications, when a user clicks "Like", "Send Message", or "Add Todo", the UI shows a loading spinner until the backend server confirms the write operation over the network (taking 200ms to 2,000ms+).

**Optimistic UI** flips this paradigm:
1. When the user takes an action, the UI **instantly updates to the expected success state** (0ms latency).
2. The asynchronous request is dispatched to the server in the background.
3. If the server confirms success, the optimistic state is replaced with the true server state seamlessly.
4. If the server fails (network drop, validation error), React **automatically rolls back the UI** to the original state and displays an error alert.

In **React 19**, the **`useOptimistic`** hook provides native, declarative support for optimistic mutations with built-in automatic rollbacks.

---

## 2. Anatomy of the `useOptimistic` Hook

```typescript
const [optimisticState, setOptimistic] = useOptimistic(
  currentState,
  (current, optimisticValue) => nextOptimisticState
);
```

- `currentState`: The true source-of-truth state passed from props or state.
- `updateFn`: Pure function that merges `currentState` with `optimisticValue` to calculate the temporary state.
- `optimisticState`: The state rendered on screen (equals `currentState` when idle, or optimistic state while an async transition is pending).
- `setOptimistic`: Dispatches temporary optimistic updates during a transition or Server Action.

---

## 3. Production Example: Optimistic Chat Message Delivery

Let's build a real-time chat interface where sent messages appear on screen immediately with a pending clock indicator:

```tsx
// src/components/ChatRoom.tsx
"use client";

import { useOptimistic, useRef, useTransition } from "react";
import { sendMessageAction } from "@/actions/chatActions";

export interface Message {
  id: string;
  text: string;
  sender: string;
  timestamp: string;
  sending?: boolean; // Optimistic flag
}

export function ChatRoom({ initialMessages }: { initialMessages: Message[] }) {
  const formRef = useRef<HTMLFormElement>(null);
  const [, startTransition] = useTransition();

  // Optimistic state wrapper:
  const [optimisticMessages, addOptimisticMessage] = useOptimistic<Message[], string>(
    initialMessages,
    (currentMessages, newText) => [
      ...currentMessages,
      {
        id: `temp_${Date.now()}`,
        text: newText,
        sender: "Me",
        timestamp: new Date().toLocaleTimeString(),
        sending: true, // Mark as currently sending
      },
    ]
  );

  async function handleSendMessage(formData: FormData) {
    const text = formData.get("message") as string;
    if (!text.trim()) return;

    formRef.current?.reset();

    // 1. Immediately apply optimistic UI update:
    startTransition(async () => {
      addOptimisticMessage(text);

      try {
        // 2. Perform background Server Action:
        await sendMessageAction(text);
      } catch (error) {
        alert("Failed to send message. Rolling back.");
      }
    });
  }

  return (
    <div className="chat-container">
      <div className="message-list">
        {optimisticMessages.map((msg) => (
          <div
            key={msg.id}
            className={`message-bubble ${msg.sending ? "message-bubble--pending" : ""}`}
          >
            <p className="message-text">{msg.text}</p>
            <span className="message-time">
              {msg.timestamp} {msg.sending && "🕒 Sending..."}
            </span>
          </div>
        ))}
      </div>

      <form ref={formRef} action={handleSendMessage} className="chat-input-form">
        <input name="message" placeholder="Type a message..." required />
        <button type="submit">Send</button>
      </form>
    </div>
  );
}
```

---

## 4. Production Example: Optimistic Like Button with Counter

```tsx
// src/components/LikeButton.tsx
"use client";

import { useOptimistic, startTransition } from "react";
import { toggleLikeAction } from "@/actions/likeActions";

export function LikeButton({
  postId,
  initialLiked,
  initialLikeCount,
}: {
  postId: string;
  initialLiked: boolean;
  initialLikeCount: number;
}) {
  const [optimisticLike, setOptimisticLike] = useOptimistic(
    { isLiked: initialLiked, count: initialLikeCount },
    (state) => ({
      isLiked: !state.isLiked,
      count: state.isLiked ? state.count - 1 : state.count + 1,
    })
  );

  async function handleClick() {
    startTransition(async () => {
      // 1. Instantly flip like state in UI
      setOptimisticLike(null);

      try {
        // 2. Persist to server
        await toggleLikeAction(postId);
      } catch (err) {
        console.error("Like failed on server");
      }
    });
  }

  return (
    <button
      onClick={handleClick}
      className={`btn-like ${optimisticLike.isLiked ? "btn-like--active" : ""}`}
    >
      <span className="heart-icon">{optimisticLike.isLiked ? "❤️" : "🤍"}</span>
      <span className="like-count">{optimisticLike.count}</span>
    </button>
  );
}
```

---

## 5. Automatic Rollback Mechanism

How does React guarantee that failed requests don't leave corrupt data on screen?

```
Optimistic Flow & Rollback:
1. True State: { count: 10 }
2. User Clicks Like ──► setOptimistic ──► UI renders { count: 11 }
3. Background Server Action:
   ├─► IF SUCCESS: Server returns { count: 11 } ──► True State becomes { count: 11 }
   └─► IF ERROR:   Server throws exception       ──► React discards optimistic layer,
                                                     reverting instantly to True State { count: 10 }!
```

---

## Troubleshooting & Best Practices

1. **`useOptimistic` Must Be Inside a Transition or Action**
   `setOptimistic` must be called inside a `startTransition` callback or a form Server Action. Calling it outside a transition will result in a React warning because React needs a transition boundary to track the lifecycle of the optimistic update.

2. **Temporary Key Identifiers**
   When optimistically appending items to a list, generate a unique temporary key (e.g. `id: 'temp_' + Date.now()`). When the real item is returned from the server with its database UUID, React smoothly reconciles the replacement.