# Module 15: Internationalization (i18n) Architecture in the App Router

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Globalization, Multi-Language Routing & Dictionaries

---

## 1. The App Router i18n Strategy: Sub-Path Routing

In the Next.js App Router, internationalization is implemented via **Sub-Path Routing** using a top-level dynamic segment: **`src/app/[lang]/...`**.

```text
Directory Structure:
src/app/
└── [lang]/
    ├── layout.tsx         ◄── Extracts [lang] and wraps the <html> lang attribute
    ├── page.tsx           ◄── Homepage (/en, /es, /fr, /de)
    ├── about/
    │   └── page.tsx       ◄── (/en/about, /es/about)
    └── dashboard/
        └── page.tsx       ◄── (/en/dashboard)
```

---

## 2. Edge Middleware for Automatic Locale Detection

When a user visits `/` without a locale prefix, the Edge Middleware inspects the browser's `Accept-Language` HTTP header and redirects to their preferred language:

```bash
npm install @formatjs/intl-localematcher negotiator
npm install -D @types/negotiator
```

```typescript
// src/middleware.ts
import { NextResponse, type NextRequest } from "next/server";
import { match as matchLocale } from "@formatjs/intl-localematcher";
import Negotiator from "negotiator";

export const locales = ["en", "es", "fr", "de", "ja"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "en";

function getPreferredLocale(request: NextRequest): string {
  // 1. Check if user already has a saved locale cookie:
  const cookieLocale = request.cookies.get("NEXT_LOCALE")?.value;
  if (cookieLocale && locales.includes(cookieLocale as any)) {
    return cookieLocale;
  }

  // 2. Parse Accept-Language header from browser:
  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => (headers[key] = value));

  const languages = new Negotiator({ headers }).languages();
  return matchLocale(languages, locales as any, defaultLocale);
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Check if pathname is missing a locale prefix:
  const pathnameIsMissingLocale = locales.every(
    (locale) => !pathname.startsWith(`/${locale}/`) && pathname !== `/${locale}`
  );

  if (pathnameIsMissingLocale) {
    const locale = getPreferredLocale(request);

    // Redirect to /[locale]/pathname (e.g. /dashboard -> /es/dashboard)
    return NextResponse.redirect(
      new URL(`/${locale}${pathname.startsWith("/") ? "" : "/"}${pathname}`, request.url)
    );
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
```

---

## 3. Server-Side Dictionaries (`getDictionary`)

Instead of shipping multi-megabyte language JSON files to the browser, **load dictionaries asynchronously on the server inside Server Components (0 KB client bundle overhead)**:

```typescript
// src/dictionaries/index.ts
import "server-only";

export type Dictionary = typeof import("./en.json");

const dictionaries = {
  en: () => import("./en.json").then((m) => m.default),
  es: () => import("./es.json").then((m) => m.default),
  fr: () => import("./fr.json").then((m) => m.default),
  de: () => import("./de.json").then((m) => m.default),
  ja: () => import("./ja.json").then((m) => m.default),
};

export const getDictionary = async (locale: string): Promise<Dictionary> => {
  const loader = dictionaries[locale as keyof typeof dictionaries] || dictionaries.en;
  return loader();
};
```

```json
// src/dictionaries/en.json
{
  "navigation": {
    "home": "Home",
    "dashboard": "Dashboard",
    "settings": "Settings"
  },
  "hero": {
    "title": "Build Fast with Next.js",
    "subtitle": "Global Edge Infrastructure",
    "cta": "Get Started Now"
  }
}
```

```json
// src/dictionaries/es.json
{
  "navigation": {
    "home": "Inicio",
    "dashboard": "Panel de Control",
    "settings": "Configuración"
  },
  "hero": {
    "title": "Construye Rápido con Next.js",
    "subtitle": "Infraestructura Global Edge",
    "cta": "Empezar Ahora"
  }
}
```

---

## 4. Consuming Dictionaries in Server Components

```tsx
// src/app/[lang]/page.tsx
import { getDictionary } from "@/dictionaries";
import { locales, type Locale } from "@/middleware";

export async function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default async function HomePage({
  params,
}: {
  params: Promise<{ lang: Locale }>;
}) {
  const { lang } = await params;
  const dict = await getDictionary(lang);

  return (
    <main className="container mx-auto py-12">
      <h1 className="text-4xl font-extrabold">{dict.hero.title}</h1>
      <p className="text-xl text-slate-400 mt-4">{dict.hero.subtitle}</p>
      <button className="btn-primary mt-6">{dict.hero.cta}</button>
    </main>
  );
}
```

---

## 5. Client-Side Language Switcher Component

```tsx
// src/components/LanguageSwitcher.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { locales, type Locale } from "@/middleware";

export function LanguageSwitcher({ currentLocale }: { currentLocale: Locale }) {
  const pathname = usePathname();
  const router = useRouter();

  function switchLocale(newLocale: Locale) {
    // Replace current locale segment in URL:
    const segments = pathname.split("/");
    segments[1] = newLocale;
    const newPath = segments.join("/");

    // Set cookie so preference persists across sessions:
    document.cookie = `NEXT_LOCALE=${newLocale}; path=/; max-age=31536000`;

    router.push(newPath);
  }

  return (
    <select
      value={currentLocale}
      onChange={(e) => switchLocale(e.target.value as Locale)}
      className="bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm"
    >
      {locales.map((l) => (
        <option key={l} value={l}>
          {l.toUpperCase()}
        </option>
      ))}
    </select>
  );
}
```

---

## Troubleshooting & Best Practices

1. **`server-only` Package for Dictionaries**
   Always place `import "server-only";` at the top of your dictionary loader file. This guarantees a compile-time error if a developer accidentally imports dictionary loader code into a Client Component.
