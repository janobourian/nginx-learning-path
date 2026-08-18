# Module 08: Optimistic UI in Next.js with `useOptimistic`

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** Asynchronous UX, Optimistic Mutations & Server Action Synchronization

---

## 1. Optimistic UI in the Next.js App Router

In the Next.js App Router, mutations typically follow this lifecycle:

1. User clicks a button in a Client Component.
2. The Client Component calls a **Server Action** (`'use server'`).
3. The server mutates the database and calls `revalidatePath('/dashboard')`.
4. Next.js re-renders the Server Components on the server and streams the fresh RSC Flight payload back to the browser.

Without Optimistic UI, the user experiences a delay between Step 1 and Step 4.

By integrating **`useOptimistic`**, the UI updates **instantly (at 0ms)** while the Server Action executes, and seamlessly transitions to the fresh server-revalidated payload upon completion.

```
Next.js Optimistic Synchronization Cycle:
[User Clicks Bookmark] ──► useOptimistic (0ms: Icon fills instantly!)
                                  │
                                  ▼ Background Network POST
                           [Server Action: db.bookmark.create()]
                                  │
                                  ▼ Server Revalidation
                           [revalidatePath('/feed')] ──► Returns fresh RSC Payload
                                  │
                                  ▼
                           [Client seamlessly transitions from optimistic to real state!]
```

---

## 2. Production Example: Optimistic Bookmark / Favorite Toggle

```tsx
// src/components/BookmarkButton.tsx
"use client";

import { useOptimistic, startTransition } from "react";
import { toggleBookmarkAction } from "@/actions/bookmarkActions";

export interface BookmarkButtonProps {
  articleId: string;
  initialIsBookmarked: boolean;
  initialBookmarkCount: number;
}

export function BookmarkButton({
  articleId,
  initialIsBookmarked,
  initialBookmarkCount,
}: BookmarkButtonProps) {
  // 1. Declare optimistic state based on server props:
  const [optimisticBookmark, setOptimisticBookmark] = useOptimistic(
    {
      isBookmarked: initialIsBookmarked,
      count: initialBookmarkCount,
    },
    (state, _action) => ({
      isBookmarked: !state.isBookmarked,
      count: state.isBookmarked ? state.count - 1 : state.count + 1,
    })
  );

  async function handleToggle() {
    // 2. Start transition to apply instant optimistic UI:
    startTransition(async () => {
      setOptimisticBookmark(null); // Trigger optimistic calculation

      try {
        // 3. Execute Server Action in background:
        await toggleBookmarkAction(articleId);
      } catch (error) {
        console.error("Failed to persist bookmark to server:", error);
      }
    });
  }

  return (
    <button
      onClick={handleToggle}
      className={`bookmark-btn ${optimisticBookmark.isBookmarked ? "bookmark-btn--active" : ""}`}
      aria-label="Bookmark article"
    >
      <span className="icon">
        {optimisticBookmark.isBookmarked ? "🔖" : "📑"}
      </span>
      <span className="count">{optimisticBookmark.count}</span>
    </button>
  );
}
```

---

## 3. The Server Action Implementation

```typescript
// src/app/actions/bookmarkActions.ts
"use server";

import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { revalidatePath } from "next/cache";

export async function toggleBookmarkAction(articleId: string) {
  const session = await auth();
  if (!session?.user?.id) {
    throw new Error("Must be logged in to bookmark articles");
  }

  const userId = session.user.id;

  const existing = await db.bookmark.findUnique({
    where: {
      userId_articleId: { userId, articleId },
    },
  });

  if (existing) {
    await db.bookmark.delete({
      where: { id: existing.id },
    });
  } else {
    await db.bookmark.create({
      data: { userId, articleId },
    });
  }

  // Revalidate the article page and feed to ensure cache is 100% synchronized!
  revalidatePath(`/articles/${articleId}`);
  revalidatePath("/feed");

  return { success: true };
}
```

---

## 4. Production Example: Optimistic Kanban Task Drag & Drop

```tsx
// src/components/KanbanBoard.tsx
"use client";

import { useOptimistic, startTransition } from "react";
import { updateTaskStatusAction } from "@/actions/taskActions";

export interface Task {
  id: string;
  title: string;
  status: "todo" | "in_progress" | "done";
}

export function KanbanBoard({ initialTasks }: { initialTasks: Task[] }) {
  const [optimisticTasks, setOptimisticTasks] = useOptimistic(
    initialTasks,
    (currentTasks, update: { taskId: string; newStatus: Task["status"] }) =>
      currentTasks.map((t) =>
        t.id === update.taskId ? { ...t, status: update.newStatus } : t
      )
  );

  function moveTask(taskId: string, newStatus: Task["status"]) {
    startTransition(async () => {
      // 1. Move card instantly in the UI:
      setOptimisticTasks({ taskId, newStatus });

      try {
        // 2. Persist to database via Server Action:
        await updateTaskStatusAction(taskId, newStatus);
      } catch (err) {
        alert("Failed to update task status");
      }
    });
  }

  const columns: Task["status"][] = ["todo", "in_progress", "done"];

  return (
    <div className="kanban-grid flex gap-4">
      {columns.map((col) => (
        <div key={col} className="kanban-col flex-1 bg-slate-900 p-4 rounded-lg">
          <h3 className="uppercase text-sm font-bold mb-4">{col.replace("_", " ")}</h3>
          <div className="space-y-2">
            {optimisticTasks
              .filter((t) => t.status === col)
              .map((task) => (
                <div key={task.id} className="task-card bg-slate-800 p-3 rounded shadow">
                  <p className="font-medium">{task.title}</p>
                  <div className="flex gap-2 mt-2">
                    {col !== "todo" && (
                      <button onClick={() => moveTask(task.id, "todo")} className="text-xs text-blue-400">
                        ← Todo
                      </button>
                    )}
                    {col !== "in_progress" && (
                      <button onClick={() => moveTask(task.id, "in_progress")} className="text-xs text-yellow-400">
                        In Progress
                      </button>
                    )}
                    {col !== "done" && (
                      <button onClick={() => moveTask(task.id, "done")} className="text-xs text-green-400">
                        Done →
                      </button>
                    )}
                  </div>
                </div>
              ))}
          </div>
        </div>
      ))}
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **State Reversion Glitches**
   If `revalidatePath()` returns data that does not match the expected optimistic update (e.g. database trigger modified other fields), you might see a brief visual jump. Ensure your Server Action's optimistic calculation precisely matches the database transformation.

2. **Always Handle Network Failures**
   When the Server Action throws an error, React automatically rolls back `useOptimistic` to the initial prop state. Always wrap your `startTransition` action call in a `try/catch` block to alert the user that the operation failed.
