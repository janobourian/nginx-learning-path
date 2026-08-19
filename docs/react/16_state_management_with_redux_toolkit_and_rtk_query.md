# Module 16: Redux Toolkit (RTK) & RTK Query Architecture

**Track:** React — Modern UI & Fiber Architecture
**Category:** Enterprise State Management & Server-State Caching

---

## 1. What Is Redux Toolkit (RTK)?

**Redux Toolkit (RTK)** is the official, opinionated, batteries-included standard for writing modern Redux logic.

Before RTK, legacy Redux required massive boilerplate: manual action types (`const ADD_TODO = 'ADD_TODO'`), action creators, switch-case reducers, manual immutable spreads (`{ ...state, items: [...state.items] }`), and configuring Redux Thunk middleware.

### What RTK Standardizes

1. **`createSlice`**: Combines action creators and reducers into a single concise declaration.
2. **Built-in Immer**: Allows writing direct "mutating" syntax (`state.count++`) which Immer converts into safe immutable updates under the hood.
3. **`configureStore`**: Automatically sets up Redux Thunk, Redux DevTools, and runtime immutability/serializability checks.
4. **RTK Query**: A powerful data-fetching and caching layer built directly into Redux.

---

## 2. Setting Up Redux Toolkit with TypeScript

```bash
npm install @reduxjs/toolkit react-redux
```

### 1. Creating a Slice (`createSlice`)

```typescript
// src/store/slices/authSlice.ts
import { createSlice, type PayloadAction } from "@reduxjs/toolkit";

export interface User {
  id: string;
  name: string;
  role: "admin" | "user";
}

export interface AuthState {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
}

const initialState: AuthState = {
  user: null,
  token: null,
  isAuthenticated: false,
};

export const authSlice = createSlice({
  name: "auth",
  initialState,
  reducers: {
    // Immer allows direct mutations safely!
    loginSuccess: (state, action: PayloadAction<{ user: User; token: string }>) => {
      state.user = action.payload.user;
      state.token = action.payload.token;
      state.isAuthenticated = true;
    },
    logout: (state) => {
      state.user = null;
      state.token = null;
      state.isAuthenticated = false;
    },
    updateUserName: (state, action: PayloadAction<string>) => {
      if (state.user) {
        state.user.name = action.payload;
      }
    },
  },
});

export const { loginSuccess, logout, updateUserName } = authSlice.actions;
export default authSlice.reducer;
```

---

## 3. Configuring the Store & Typed Hooks

```typescript
// src/store/index.ts
import { configureStore } from "@reduxjs/toolkit";
import { type TypedUseSelectorHook, useDispatch, useSelector } from "react-redux";
import authReducer from "./slices/authSlice";
import { postsApi } from "./api/postsApi";

export const store = configureStore({
  reducer: {
    auth: authReducer,
    [postsApi.reducerPath]: postsApi.reducer, // RTK Query Reducer
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware().concat(postsApi.middleware),
});

// Infer RootState and AppDispatch types
export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;

// Export typed hooks throughout your app instead of plain useDispatch / useSelector
export const useAppDispatch: () => AppDispatch = useDispatch;
export const useAppSelector: TypedUseSelectorHook<RootState> = useSelector;
```

---

## 4. Server-State Caching with RTK Query

**RTK Query** eliminates the need to write manual async thunks, loading flags, and error states for HTTP requests.

```typescript
// src/store/api/postsApi.ts
import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";

export interface Post {
  id: string;
  title: string;
  content: string;
  author: string;
}

export const postsApi = createApi({
  reducerPath: "postsApi",
  baseQuery: fetchBaseQuery({
    baseUrl: "https://api.example.com/v1",
    prepareHeaders: (headers, { getState }) => {
      const token = (getState() as { auth: { token: string | null } }).auth.token;
      if (token) {
        headers.set("Authorization", `Bearer ${token}`);
      }
      return headers;
    },
  }),
  tagTypes: ["Posts"], // Tag for automated cache invalidation
  endpoints: (builder) => ({
    // 1. Query: Fetch all posts
    getPosts: builder.query<Post[], void>({
      query: () => "/posts",
      providesTags: (result) =>
        result
          ? [
              ...result.map(({ id }) => ({ type: "Posts" as const, id })),
              { type: "Posts", id: "LIST" },
            ]
          : [{ type: "Posts", id: "LIST" }],
    }),

    // 2. Query: Fetch single post by ID
    getPostById: builder.query<Post, string>({
      query: (id) => `/posts/${id}`,
      providesTags: (_result, _error, id) => [{ type: "Posts", id }],
    }),

    // 3. Mutation: Create new post & auto-invalidate list cache!
    createPost: builder.mutation<Post, Partial<Post>>({
      query: (body) => ({
        url: "/posts",
        method: "POST",
        body,
      }),
      // Invalidate the LIST tag to automatically trigger background re-fetching of getPosts:
      invalidatesTags: [{ type: "Posts", id: "LIST" }],
    }),
  }),
});

// Auto-generated hooks for components!
export const {
  useGetPostsQuery,
  useGetPostByIdQuery,
  useCreatePostMutation,
} = postsApi;
```

---

## 5. Consuming RTK Query in Components

```tsx
import { useState } from "react";
import { useGetPostsQuery, useCreatePostMutation } from "@/store/api/postsApi";
import { useAppSelector } from "@/store";

export function PostManagementView() {
  const [newTitle, setNewTitle] = useState("");
  const isAuthenticated = useAppSelector((state) => state.auth.isAuthenticated);

  // RTK Query hook handles data, loading, polling, and errors automatically:
  const { data: posts, isLoading, error, refetch } = useGetPostsQuery(undefined, {
    pollingInterval: 30000, // Background poll every 30 seconds
  });

  const [createPost, { isLoading: isCreating }] = useCreatePostMutation();

  async function handleCreate() {
    if (!newTitle.trim()) return;
    await createPost({ title: newTitle, content: "Post body...", author: "Admin" });
    setNewTitle("");
  }

  if (isLoading) return <p>Loading articles...</p>;
  if (error) return <p className="error">Failed to load articles</p>;

  return (
    <div className="posts-container">
      <h2>Articles Feed</h2>
      <button onClick={() => refetch()}>Force Refresh</button>

      {isAuthenticated && (
        <div className="create-box">
          <input
            value={newTitle}
            onChange={(e) => setNewTitle(e.target.value)}
            placeholder="Article title..."
          />
          <button onClick={handleCreate} disabled={isCreating}>
            {isCreating ? "Saving..." : "Add Post"}
          </button>
        </div>
      )}

      <ul>
        {posts?.map((post) => (
          <li key={post.id}>
            <strong>{post.title}</strong> — by {post.author}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Do Not Mix Server State into Slice State**
   Avoid manually storing API fetched data inside standard `createSlice` reducers. Use **RTK Query** for all server caching, pagination, and invalidation, keeping client slices focused exclusively on local UI state.

2. **Always Use `prepareHeaders` for Token Injection**
   Inject authentication tokens inside `prepareHeaders` rather than manually passing headers to individual query hooks.
