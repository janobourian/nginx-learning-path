# Module 14: Dynamic SEO Metadata & OpenGraph Image Generation

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Search Engine Optimization (SEO), Metadata & Social Share Cards

---

## 1. The Metadata API in the App Router

The Next.js App Router replaces legacy `<Head>` components with the **Metadata API**. Metadata can be declared statically or generated dynamically based on asynchronous data.

Next.js automatically constructs valid HTML5 `<meta>`, `<link>`, OpenGraph, and Twitter Card tags in the page `<head>`.

---

## 2. Static vs Dynamic Metadata

### 1. Static Metadata with Title Templates

```tsx
// src/app/about/page.tsx
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "About Our Mission",
  description: "Learn about Acme's global edge infrastructure.",
  keywords: ["Cloud", "Edge Computing", "Next.js", "Enterprise"],
  alternates: {
    canonical: "https://acme.example.com/about",
  },
  openGraph: {
    title: "About Acme Cloud",
    description: "Global high-availability cloud platform.",
    url: "https://acme.example.com/about",
    siteName: "Acme Cloud",
    images: [
      {
        url: "https://acme.example.com/og-about.png",
        width: 1200,
        height: 630,
        alt: "Acme Cloud Infrastructure",
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    site: "@acme_cloud",
    creator: "@acme_team",
  },
};

export default function AboutPage() {
  return <h1>About Us</h1>;
}
```

### 2. Dynamic Metadata (`generateMetadata`)

For dynamic routes (e.g. `/blog/[slug]` or `/products/[id]`), export an async `generateMetadata` function:

```tsx
// src/app/blog/[slug]/page.tsx
import type { Metadata } from "next";
import { db } from "@/lib/db";
import { notFound } from "next/navigation";

interface PageProps {
  params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params;
  const post = await db.post.findUnique({ where: { slug } });

  if (!post) return { title: "Post Not Found" };

  return {
    title: post.title,
    description: post.summary,
    openGraph: {
      title: post.title,
      description: post.summary,
      publishedTime: post.publishedAt.toISOString(),
      authors: [post.authorName],
      images: [
        {
          url: `/blog/${slug}/opengraph-image`, // Dynamically generated OG image!
          width: 1200,
          height: 630,
          alt: post.title,
        },
      ],
    },
  };
}

export default async function BlogPostPage({ params }: PageProps) {
  const { slug } = await params;
  const post = await db.post.findUnique({ where: { slug } });
  if (!post) notFound();
  return <article><h1>{post.title}</h1></article>;
}
```

---

## 3. Dynamic OpenGraph Image Generation (`next/og` & `ImageResponse`)

Next.js includes **`@vercel/og`** (powered by Satori and Resvg) to **generate dynamic, branded 1200x630 social share images using JSX and Flexbox CSS on-the-fly at the Edge**:

```tsx
// src/app/blog/[slug]/opengraph-image.tsx
import { ImageResponse } from "next/og";
import { db } from "@/lib/db";

export const runtime = "edge"; // Generate images in <50ms at Edge locations!
export const alt = "Article Social Preview";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await db.post.findUnique({ where: { slug } });

  const title = post?.title || "Enterprise Next.js Architecture";
  const author = post?.authorName || "Engineering Team";

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 80,
          backgroundColor: "#020617",
          color: "#f8fafc",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <div
            style={{
              width: 48,
              height: 48,
              borderRadius: "50%",
              backgroundColor: "#3b82f6",
            }}
          />
          <span style={{ fontSize: 28, fontWeight: 700, letterSpacing: "-0.05em" }}>
            ACME ENGINEERING BLOG
          </span>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <h1
            style={{
              fontSize: 64,
              fontWeight: 800,
              lineHeight: 1.1,
              letterSpacing: "-0.03em",
              color: "#ffffff",
            }}
          >
            {title}
          </h1>
          <p style={{ fontSize: 28, color: "#94a3b8" }}>By {author}</p>
        </div>

        <div style={{ display: "flex", justifyContent: "space-between", borderTop: "2px solid #1e293b", paddingTop: 24 }}>
          <span style={{ fontSize: 22, color: "#64748b" }}>acme.example.com</span>
          <span style={{ fontSize: 22, color: "#3b82f6" }}>Read Article →</span>
        </div>
      </div>
    ),
    { ...size }
  );
}
```

---

## 4. Automated `sitemap.ts` and `robots.ts`

```typescript
// src/app/sitemap.ts
import type { MetadataRoute } from "next";
import { db } from "@/lib/db";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const posts = await db.post.findMany({ select: { slug: true, updatedAt: true } });

  const postUrls = posts.map((p) => ({
    url: `https://acme.example.com/blog/${p.slug}`,
    lastModified: p.updatedAt,
    changeFrequency: "weekly" as const,
    priority: 0.8,
  }));

  return [
    {
      url: "https://acme.example.com",
      lastModified: new Date(),
      changeFrequency: "daily",
      priority: 1.0,
    },
    {
      url: "https://acme.example.com/about",
      lastModified: new Date(),
      changeFrequency: "monthly",
      priority: 0.5,
    },
    ...postUrls,
  ];
}
```

```typescript
// src/app/robots.ts
import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: ["/admin/", "/api/", "/dashboard/private/"],
    },
    sitemap: "https://acme.example.com/sitemap.xml",
  };
}
```

---

## Troubleshooting & Best Practices

1. **Request Memoization in `generateMetadata`**
   If both `generateMetadata` and `page.tsx` fetch the same post (`await db.post.findUnique(...)`), wrap the database call in `React.cache()` (Module 04) to avoid executing duplicate database queries.
