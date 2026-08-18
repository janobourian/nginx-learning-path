# Module 17: React Router v7 — Data Loaders, Actions & Nested Layouts

**Track:** React — Modern UI & Fiber Architecture  
**Category:** Client-Side Routing & Data-Driven Architecture

---

## 1. What Is React Router v7 & the Data Router?

Historically, client-side React routing followed the "Fetch-on-Render" waterfall model:
1. React Router rendered the `<Dashboard />` component.
2. The component mounted and triggered `useEffect(() => fetch('/api/user'))`.
3. When the user data returned, it rendered `<ChildList />`, which triggered *another* `useEffect(() => fetch('/api/items'))`.

**React Router v7** (which merges the Remix framework architecture into React Router core) introduces the **Data Router**. 

With Data Routers:
- **Loaders** fetch all data in parallel **before** the component starts rendering, eliminating network waterfalls completely!
- **Actions** handle form submissions and mutations, automatically triggering background revalidation of all active loaders.

```
Traditional Waterfall (Fetch-on-Render):
[Route Change] ──► Render Parent ──► useEffect (100ms) ──► Render Child ──► useEffect (100ms) ──► Total: 200ms

React Router v7 Parallel Data Loading:
[Route Change] ──► [Parent Loader (100ms)] ──┐
               ──► [Child Loader (100ms)]  ──┴──► Both resolve in parallel ──► Render UI (Total: 100ms!)
```

---

## 2. Setting Up `createBrowserRouter`

```bash
npm install react-router-dom
```

```tsx
// src/router/index.tsx
import { createBrowserRouter, redirect } from "react-router-dom";
import { RootLayout } from "@/layouts/RootLayout";
import { DashboardLayout } from "@/layouts/DashboardLayout";
import { ProjectsView, projectsLoader } from "@/views/ProjectsView";
import { ProjectDetailView, projectDetailLoader, projectAction } from "@/views/ProjectDetailView";
import { ErrorPage } from "@/views/ErrorPage";

export const router = createBrowserRouter([
  {
    path: "/",
    element: <RootLayout />,
    errorElement: <ErrorPage />, // Global Error Boundary
    children: [
      {
        path: "dashboard",
        element: <DashboardLayout />,
        // Protected Route check inside loader before rendering!
        loader: async () => {
          const token = localStorage.getItem("auth_token");
          if (!token) {
            return redirect("/login?from=/dashboard");
          }
          return null;
        },
        children: [
          {
            path: "projects",
            element: <ProjectsView />,
            loader: projectsLoader,
          },
          {
            path: "projects/:projectId",
            element: <ProjectDetailView />,
            loader: projectDetailLoader,
            action: projectAction,
          },
        ],
      },
    ],
  },
]);
```

---

## 3. Data Loaders & `useLoaderData`

A **Loader** is an async function that runs before the route renders:

```tsx
// src/views/ProjectsView.tsx
import { useLoaderData, Link, type LoaderFunctionArgs } from "react-router-dom";

export interface Project {
  id: string;
  name: string;
  status: "active" | "archived";
}

// 1. Define the Route Loader
export async function projectsLoader({ request }: LoaderFunctionArgs) {
  const url = new URL(request.url);
  const filter = url.searchParams.get("filter") || "all";

  const response = await fetch(`/api/projects?filter=${filter}`);
  if (!response.ok) {
    throw new Response("Failed to load projects from API", { status: response.status });
  }

  const projects: Project[] = await response.json();
  return { projects, filter };
}

// 2. Consume Data in Component with 100% Type Safety
export function ProjectsView() {
  const { projects, filter } = useLoaderData() as Awaited<ReturnType<typeof projectsLoader>>;

  return (
    <div className="projects-view">
      <h2>Projects (Filter: {filter})</h2>
      <div className="project-list">
        {projects.map((project) => (
          <article key={project.id} className="project-card">
            <h3>{project.name}</h3>
            <Link to={`/dashboard/projects/${project.id}`}>View Details</Link>
          </article>
        ))}
      </div>
    </div>
  );
}
```

---

## 4. Route Actions & Automatic Revalidation

An **Action** handles data mutations (POST, PUT, DELETE). Whenever an action finishes executing, **React Router automatically re-calls all active loaders on the page** so your UI updates instantly:

```tsx
// src/views/ProjectDetailView.tsx
import {
  useLoaderData,
  useNavigation,
  Form,
  type ActionFunctionArgs,
  type LoaderFunctionArgs,
} from "react-router-dom";

export async function projectDetailLoader({ params }: LoaderFunctionArgs) {
  const res = await fetch(`/api/projects/${params.projectId}`);
  if (!res.ok) throw new Response("Project Not Found", { status: 404 });
  return (await res.json()) as { id: string; name: string; description: string };
}

export async function projectAction({ request, params }: ActionFunctionArgs) {
  const formData = await request.formData();
  const name = formData.get("name") as string;
  const description = formData.get("description") as string;

  const res = await fetch(`/api/projects/${params.projectId}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, description }),
  });

  if (!res.ok) {
    return { error: "Failed to update project" };
  }

  return { success: true };
}

export function ProjectDetailView() {
  const project = useLoaderData() as Awaited<ReturnType<typeof projectDetailLoader>>;
  const navigation = useNavigation();

  // True while form submission or page navigation is in flight:
  const isSubmitting = navigation.state === "submitting";

  return (
    <div className="project-detail">
      <h1>Edit {project.name}</h1>

      {/* Declarative HTML Form with Client-Side Routing Interception */}
      <Form method="post" className="edit-form">
        <div>
          <label>Project Name</label>
          <input name="name" defaultValue={project.name} required />
        </div>

        <div>
          <label>Description</label>
          <textarea name="description" defaultValue={project.description} />
        </div>

        <button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Saving..." : "Save Changes"}
        </button>
      </Form>
    </div>
  );
}
```

---

## 5. Layouts & `<Outlet />`

```tsx
// src/layouts/DashboardLayout.tsx
import { Outlet, NavLink, useNavigation } from "react-router-dom";

export function DashboardLayout() {
  const navigation = useNavigation();

  return (
    <div className="dashboard-shell">
      {/* Top Global Loading Bar */}
      {navigation.state === "loading" && <div className="route-loading-bar" />}

      <aside className="sidebar">
        <nav>
          <NavLink to="/dashboard/projects" end>Projects</NavLink>
          <NavLink to="/dashboard/analytics">Analytics</NavLink>
        </nav>
      </aside>

      <main className="main-content">
        {/* Child routes render right here! */}
        <Outlet />
      </main>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Throwing `Response` Objects in Loaders**
   When an error occurs (e.g. 404 or 401), `throw new Response("Message", { status: 404 })` inside your loader. React Router automatically catches this and renders the nearest `errorElement` boundary.

2. **Use `<Form>` instead of plain `<form>`**
   The `<Form>` component from `react-router-dom` prevents default browser full-page reloads and submits data through your route action via client-side fetch.