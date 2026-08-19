# Module 10: React Fiber Reconciliation & Double Buffering Architecture

**Track:** React — Modern UI & Fiber Architecture
**Category:** React Internals, Fiber Data Structures & Scheduling Engine

---

## 1. Why React Needed the Fiber Reconciler

In React 15 and earlier, React used the **Stack Reconciler**.

When state changed, the Stack Reconciler recursively walked the entire Virtual DOM tree using JavaScript's native call stack. Because a recursive function cannot be paused until it completes:

- For large component trees (10,000+ nodes), reconciliation took 30ms to 100ms+.
- The JavaScript main thread remained completely blocked.
- User typing input, scrolling, and CSS animations dropped frames (dropping below 60fps), causing visible UI stutter (jank).

**React Fiber** (introduced in React 16 and evolved in React 18/19) is a complete rewrite of React's core algorithm. Fiber converts the recursive call stack into a **virtual stack frame implemented as a singly-linked list of objects (Fibers)** that can be paused, aborted, resumed, or prioritized.

---

## 2. The Fiber Node Data Structure

A **Fiber** is a plain JavaScript object representing a unit of work and a component instance in the tree:

```typescript
// The core properties of a React Fiber Node:
interface FiberNode {
  // ─── 1. Instance Identification ───
  tag: WorkTag;              // Type of Fiber (FunctionComponent, ClassComponent, HostRoot, HostComponent)
  key: null | string;        // Unique identifier for list diffing
  elementType: any;          // The underlying function/class/tag
  type: any;                 // Resolved component type
  stateNode: any;            // Reference to the real DOM element or Class instance

  // ─── 2. Fiber Tree Topology (Singly-Linked List) ───
  return: FiberNode | null;  // Parent Fiber (where to return after completing work)
  child: FiberNode | null;   // First child Fiber
  sibling: FiberNode | null; // Next sibling Fiber

  // ─── 3. Dynamic State & Props ───
  pendingProps: any;         // Props passed in this render
  memoizedProps: any;        // Props used in the previous render
  memoizedState: any;        // Linked list of Hook states (useState, useEffect)
  updateQueue: any;          // Queue of pending state updates and effects

  // ─── 4. Side Effect & Mutation Flags ───
  flags: Flags;              // Bitmask flags (Placement, Update, Deletion, Passive)
  subtreeFlags: Flags;       // Bitmask summarizing all descendant flags for fast traversal

  // ─── 5. Double Buffering Pointer ───
  alternate: FiberNode | null; // Pointer to the corresponding node in the other tree!
}
```

---

## 3. Fiber Tree Topology (Linked List Navigation)

Instead of nesting child arrays, Fiber trees use three pointers: **`child`**, **`sibling`**, and **`return`**:

```text
Component Tree:
       [App]
      /     \
   [Nav]   [Main]
           /    \
       [Feed]  [Sidebar]

Fiber Linked List Representation:
[App Fiber]
  │ child
  ▼
[Nav Fiber] ── sibling ──► [Main Fiber]
  │                          │ child
  │ return                   ▼
  └────────────────────────► [Feed Fiber] ── sibling ──► [Sidebar Fiber]
                               │                           │ return
                               └───────────────────────────┴──────────► [Main Fiber]
```

This linked-list structure allows the reconciler to pause work at any node, store the current pointer in a global variable (`workInProgress`), yield control back to the browser event loop, and resume later right where it left off.

---

## 4. The Double Buffering Algorithm

To ensure smooth rendering without displaying half-rendered, broken UI states, React maintains **two Fiber trees simultaneously** in memory (a technique borrowed from graphics game engines):

1. **The `current` Tree**: Represents the UI currently painted and visible on the user's screen.
2. **The `workInProgress` (WIP) Tree**: The tree being actively constructed, diffed, and calculated in memory.

```text
Double Buffering Swap:

Screen Display ──► [Current Tree Node]
                          │          ▲
                alternate │          │ alternate
                          ▼          │
                   [WorkInProgress Tree Node] ◄── Background reconciliation
                                                         │
                                                         ▼
                                                Commit Phase:
                                      Root Pointer Swaps to WIP Tree!
```

During reconciliation, React builds the `workInProgress` tree by cloning `current` nodes and reusing their `alternate` references. Once all work is complete, React commits the entire WIP tree to the real DOM in a single atomic step and swaps the root pointer (`current = workInProgress`).

---

## 5. The Two Phases: Render vs Commit

```text
┌─────────────────────────────────────────────────────────────┐
│             Phase 1: Render / Reconciliation                │
│  • Asynchronous & Interruptible                             │
│  • Walks Fiber tree, executes component functions & hooks   │
│  • Performs diffing algorithm                               │
│  • Tags Fibers with effect flags (Placement, Update, etc.)  │
│  • ZERO mutations to the real DOM                           │
└──────────────────────────────┬──────────────────────────────┘
                               │ Completed WIP Tree
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  Phase 2: Commit Phase                      │
│  • Synchronous & Uninterruptible                            │
│  • Sub-phase 1: Mutation (Applies real DOM insertions/edits)│
│  • Sub-phase 2: Layout (Executes useLayoutEffect hooks)     │
│  • Browser Paint (User sees new frame)                      │
│  • Sub-phase 3: Passive Effects (Executes useEffect hooks)  │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. The Work Loop & Time Slicing

The core engine of React's concurrent scheduler is the **`workLoopConcurrent`**:

```typescript
// Conceptual implementation of React's internal work loop:
function workLoopConcurrent() {
  // Perform work on the current Fiber while there is still work and browser time remaining:
  while (workInProgress !== null && !shouldYieldToHost()) {
    performUnitOfWork(workInProgress);
  }
}

function shouldYieldToHost(): boolean {
  // Uses MessageChannel / performance.now() to check if 5ms time slice has elapsed:
  return performance.now() >= deadline;
}
```

If `shouldYieldToHost()` returns `true` (5ms elapsed):

1. React pauses the work loop.
2. Yields control back to the browser to process clicks, mouse events, and CSS animations.
3. Posts a message to the browser task queue to resume the work loop in the next event loop tick.

---

## Troubleshooting & Architecture Insights

1. **Why Pure Renders Are Mandatory**
   Because the **Render Phase** is interruptible and can be restarted or thrown away in Concurrent Mode, any side effect placed in the render body will execute multiple times unpredictably.

2. **Why Hook Order Must Never Change**
   Inside the Fiber node, `memoizedState` is a **singly-linked list of hook objects**. React identifies hooks solely by their index position in this linked list. If an `if` condition skips a hook, all subsequent hooks read the wrong state from the list, causing immediate runtime corruption.
