# Module 06: Server Actions — RPC Mutations, Security & File Uploads

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Server Mutations, Security Architecture & File Streaming

---

## 1. What Are Server Actions?

**Server Actions** are asynchronous JavaScript functions that execute strictly on the server environment. They can be called directly from Client Components or passed to standard HTML `<form>` elements without manually defining API routes (`/api/mutate`) or managing `fetch` boilerplate.

Under the hood:

- Next.js automatically assigns a unique RPC endpoint hash to the action.
- Next.js sends a `POST` request with encrypted Action ID headers.
- Next.js runs the action on the server and streams back revalidated RSC payloads.

---

## 2. Server Action Security (Authentication, CSRF & Zod Validation)

Because Server Actions are publicly exposed POST endpoints, **treat every Server Action with the exact same security rigor as a public REST API**:

1. **Authentication Check**: Verify the user's session token inside the action body.
2. **Authorization (RBAC)**: Verify the user has permission to mutate the specific resource.
3. **Schema Validation**: Validate input payloads using Zod to prevent injection attacks.
4. **Built-in CSRF Protection**: Next.js automatically validates `Origin` and `Host` request headers for Server Actions to block cross-site request forgery.

```typescript
// src/app/actions/userActions.ts
"use server";

import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { revalidatePath } from "next/cache";
import { z } from "zod";

const UpdateProfileSchema = z.object({
  name: z.string().min(2).max(50),
  bio: z.string().max(300).optional(),
});

export async function updateProfile(formData: FormData) {
  // 1. Authentication Gate
  const session = await auth();
  if (!session?.user?.id) {
    throw new Error("Unauthorized: You must be logged in to update your profile");
  }

  // 2. Validate Payload with Zod
  const rawData = {
    name: formData.get("name"),
    bio: formData.get("bio") || undefined,
  };

  const validation = UpdateProfileSchema.safeParse(rawData);
  if (!validation.success) {
    return {
      success: false,
      errors: validation.error.flatten().fieldErrors,
    };
  }

  // 3. Database Mutation
  await db.user.update({
    where: { id: session.user.id },
    data: validation.data,
  });

  // 4. Revalidate cache
  revalidatePath("/profile");
  return { success: true };
}
```

---

## 3. Cookie Management & Redirects in Server Actions

Server Actions have direct read/write access to HTTP cookies and can initiate redirects:

```typescript
// src/app/actions/authActions.ts
"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

export async function loginAction(formData: FormData) {
  const email = formData.get("email") as string;
  const password = formData.get("password") as string;

  const sessionToken = await authenticateWithBackend(email, password);

  if (!sessionToken) {
    return { error: "Invalid credentials" };
  }

  // Set secure, HTTP-only cookie on the client:
  const cookieStore = await cookies();
  cookieStore.set("auth_token", sessionToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7, // 7 days
  });

  // Redirect to protected dashboard:
  redirect("/dashboard");
}

export async function logoutAction() {
  const cookieStore = await cookies();
  cookieStore.delete("auth_token");
  redirect("/login");
}
```

---

## 4. Handling File Uploads Directly via Server Actions

Next.js Server Actions can process multipart file uploads directly and stream them to S3, Cloudflare R2, or local storage:

```typescript
// src/app/actions/uploadActions.ts
"use server";

import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  region: process.env.AWS_REGION || "us-east-1",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || "",
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || "",
  },
});

export async function uploadAvatarAction(formData: FormData) {
  const file = formData.get("avatar") as File | null;

  if (!file || file.size === 0) {
    return { error: "No file provided" };
  }

  // Validate File Size & MIME type
  if (file.size > 5 * 1024 * 1024) { // 5MB limit
    return { error: "File exceeds 5MB limit" };
  }

  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
    return { error: "Only JPEG, PNG, and WebP images are allowed" };
  }

  const bytes = await file.arrayBuffer();
  const buffer = Buffer.from(bytes);
  const key = `avatars/${Date.now()}-${file.name.replace(/\s+/g, "_")}`;

  // Stream to S3
  await s3.send(
    new PutObjectCommand({
      Bucket: process.env.AWS_S3_BUCKET,
      Key: key,
      Body: buffer,
      ContentType: file.type,
    })
  );

  const publicUrl = `https://${process.env.AWS_S3_BUCKET}.s3.amazonaws.com/${key}`;
  return { success: true, url: publicUrl };
}
```

```tsx
// src/components/AvatarUploadForm.tsx
"use client";

import { useState } from "react";
import { uploadAvatarAction } from "@/actions/uploadActions";

export function AvatarUploadForm() {
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  async function handleUpload(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);

    setIsUploading(true);
    const res = await uploadAvatarAction(formData);
    setIsUploading(false);

    if (res.success && res.url) {
      setPreviewUrl(res.url);
    } else {
      alert(res.error);
    }
  }

  return (
    <form onSubmit={handleUpload} className="upload-box">
      <input type="file" name="avatar" accept="image/*" required />
      <button type="submit" disabled={isUploading}>
        {isUploading ? "Uploading to Cloud..." : "Upload Avatar"}
      </button>
      {previewUrl && <img src={previewUrl} alt="Uploaded Avatar" className="w-24 h-24 rounded-full mt-4" />}
    </form>
  );
}
```

---

## Troubleshooting & Best Practices

1. **`redirect()` inside `try/catch`**
   In Next.js, `redirect()` works by throwing a special internal JavaScript exception (`NEXT_REDIRECT`). If you place `redirect()` inside a `try/catch` block, re-throw the error in `catch` or call `redirect()` *outside* the `try/catch` block.

2. **File Size Limit Config**
   By default, Next.js limits Server Action request bodies to 1MB. To allow larger file uploads, adjust `experimental.serverActions.bodySizeLimit: '10mb'` in `next.config.ts`.
