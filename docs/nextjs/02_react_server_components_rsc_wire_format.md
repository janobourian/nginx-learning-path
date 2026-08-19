# Module 02: React Server Components (RSC) & Flight Wire Format

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Server Component Architecture & Network Serialization Protocols

---

## 1. The Core Architecture of React Server Components (RSC)

In traditional Single Page Applications, all components are client-side JavaScript. To render a markdown blog post, the browser had to download the React runtime, the component tree, and heavy markdown parsing libraries (e.g. `marked`, `highlight.js`, `sanitize-html` totaling 250KB+).

With **React Server Components (RSC)**:

1. Components execute **strictly on the server**.
2. Heavy libraries (`marked`, `shiki`, Prisma ORM) execute on the server and are **completely stripped from the client bundle (0 KB sent to client)**.
3. The server streams a lightweight virtual description of the UI called the **Flight Wire Format**.
4. The client merges this stream directly into the live DOM tree.

```text
Traditional Client Bundle vs RSC Execution:
Traditional SPA:
  Server ──► [250KB JS Bundle + Markdown Parser + DB Fetch Code] ──► Browser parses & renders

React Server Components (RSC):
  Server (Runs Markdown Parser + SQL query) ──► [3KB Flight Stream Payload] ──► Browser renders instantly!
```

---

## 2. Dissecting the RSC Flight Wire Format

When a user navigates between routes in Next.js App Router, the server does not send full HTML pages. It streams line-delimited JSON chunks representing the React component tree and unresolved Promises:

```text
M1:{"id":"./src/components/AddToCartButton.tsx","chunks":["client-chunk-123.js"],"name":"AddToCartButton"}
J0:["$","div",null,{"className":"product-page","children":[
  ["$","h1",null,{"children":"Mechanical Keyboard"}],
  ["$","p",null,{"children":"Price: $149.99"}],
  ["$","$L1",null,{"productId":"prod_99"}]
]}]
```

### Decoding the Flight Protocol

- **`M1` (Module Reference)**: Tells the client that component `$L1` is a **Client Component** located in `AddToCartButton.tsx` and tells the browser to load `client-chunk-123.js`.
- **`J0` (JSON Node Descriptor)**: Describes the virtual DOM tree (`["$", "tag", key, props]`).
- Notice that static HTML tags (`h1`, `p`, `div`) are serialized as plain descriptors, while interactive islands are marked with module references (`$L1`).

---

## 3. Zero-Bundle-Size Server Components

Let's render a code snippet with heavy syntax highlighting (`shiki`) inside a Server Component:

```tsx
// src/components/CodeBlockServer.tsx (Server Component: 0 KB JS sent to browser!)
import { codeToHtml } from "shiki";

export async function CodeBlockServer({
  code,
  language,
}: {
  code: string;
  language: string;
}) {
  // 'shiki' syntax highlighting engine runs strictly on the server:
  const html = await codeToHtml(code, {
    lang: language,
    theme: "nord",
  });

  return (
    <div
      className="code-snippet"
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
```

Because `CodeBlockServer` is a Server Component, the multi-megabyte `shiki` WebAssembly bundle is **never downloaded by the client browser**. The browser only receives the lightweight highlighted HTML!

---

## 4. Composing Server and Client Components

A common question in App Router architecture: *Can a Client Component import a Server Component?*

### The Golden Composition Rules

1. **Server Components CAN directly import and render Client Components**:

   ```tsx
   // Server Component (app/page.tsx)
   import { ClientInteractiveChart } from "@/components/ClientInteractiveChart"; // Valid!

   export default async function Page() {
     const data = await db.query();
     return <ClientInteractiveChart initialData={data} />;
   }
   ```

2. **Client Components CANNOT directly import Server Components**:

   ```tsx
   "use client";
   // ❌ INVALID: Importing a Server Component into a Client Component converts it to a Client Component!
   // import { ServerDatabaseReader } from "./ServerDatabaseReader";
   ```

3. **Client Components CAN accept Server Components as `children` or props!** (The Slot Pattern):

   ```tsx
   "use client";

   // Client Component acting as an interactive container / modal:
   export function InteractiveModal({ children }: { children: React.ReactNode }) {
     const [isOpen, setIsOpen] = useState(false);
     return (
       <div>
         <button onClick={() => setIsOpen(true)}>Open Details</button>
         {isOpen && <div className="modal-body">{children}</div>}
       </div>
     );
   }
   ```

   ```tsx
   // Server Component (app/page.tsx)
   export default async function Page() {
     return (
       <InteractiveModal>
         {/* This Server Component executes on the server and is passed as a child slot! */}
         <ServerHeavyDatabaseReport />
       </InteractiveModal>
     );
   }
   ```

---

## Troubleshooting & Best Practices

1. **Do not use Context Providers in Server Components**
   React Context (`createContext`, `useContext`) is a client-side feature. If your application requires global context providers (e.g. Theme, React Query), create a client wrapper component (`'use client'`) and render it inside your root `layout.tsx`.

2. **Do not access `window` or `document` in Server Components**
   Server Components execute in Node.js / Edge workers where browser globals do not exist. Wrap browser-specific code in `'use client'` components and access globals inside `useEffect()`.
