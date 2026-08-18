# Module 13: Asset Optimization — `next/font`, `next/image` & Core Web Vitals

**Track:** Next.js — Full-Stack App Router & Edge Architecture  
**Category:** Media Processing, Font Subsetting & Web Vitals Optimization

---

## 1. Zero-Layout-Shift Font Optimization with `next/font`

Historically, loading external fonts (e.g. from `fonts.googleapis.com`) caused significant performance issues:
1. **Network Latency & Privacy Concerns**: An extra DNS lookup and HTTP connection to Google's servers on every page load.
2. **Flash of Invisible Text (FOIT)** or **Flash of Unstyled Text (FOUT)**.
3. **Cumulative Layout Shift (CLS)**: When the custom font finally loaded, text changed size and reflowed the entire page layout.

**`next/font`** automatically:
- **Downloads and self-hosts font files at build time** (zero requests sent to Google at runtime).
- **Subsets the font** (only includes characters for selected languages, e.g. `latin`, reducing file size by 80%).
- **Computes CSS fallback metrics (`size-adjust`)** so the fallback system font matches the exact dimensions of the custom font, **guaranteeing Cumulative Layout Shift (CLS) = 0!**

```tsx
// src/app/layout.tsx
import { Inter, Roboto_Mono, Playfair_Display } from "next/font/google";
import localFont from "next/font/local";

// 1. Variable Google Font
export const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

// 2. Monospace Font for Code
export const robotoMono = Roboto_Mono({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-mono",
});

// 3. Custom Local Font Files
export const customBrandFont = localFont({
  src: [
    { path: "../assets/fonts/Brand-Regular.woff2", weight: "400", style: "normal" },
    { path: "../assets/fonts/Brand-Bold.woff2", weight: "700", style: "normal" },
  ],
  variable: "--font-brand",
});
```

---

## 2. Advanced Image Optimization with `next/image`

The HTML `<img>` tag delivers uncompressed, full-resolution images regardless of the user's screen size. Loading a 4MB 4000x3000px image on a mobile phone wastes user mobile data and ruins Largest Contentful Paint (LCP).

The **`next/image`** component automatically:
1. **Converts images to modern WebP and AVIF formats** on-the-fly.
2. **Resizes images** to the exact viewport dimension of the requesting device.
3. **Lazy-loads offscreen images** natively as the user scrolls.
4. **Prevents Cumulative Layout Shift** by reserving exact aspect-ratio space in the DOM.

```tsx
import Image from "next/image";
import heroPoster from "@/assets/images/hero-poster.jpg";

export function HeroBanner() {
  return (
    <section className="hero-container">
      {/* 1. Statically Imported Image (Width, height & blur placeholder computed automatically!) */}
      <Image
        src={heroPoster}
        alt="Next.js Enterprise Cloud Infrastructure"
        placeholder="blur" // Instant low-res blur-up effect!
        priority={true}   // Preloads above-the-fold image immediately (Boosts LCP!)
        className="rounded-xl shadow-2xl"
      />

      {/* 2. Responsive Remote Image with 'fill' and 'sizes' */}
      <div className="relative w-full h-96 mt-8">
        <Image
          src="https://images.unsplash.com/photo-1550745165-9bc0b252726f"
          alt="Modern Tech Lab"
          fill // Fills the parent <div> container
          sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
          className="object-cover rounded-lg"
        />
      </div>
    </section>
  );
}
```

### Understanding the `sizes` Attribute

The `sizes` attribute tells the browser how wide the image will be on different screen sizes:
- `(max-width: 768px) 100vw`: On mobile screens (<768px), the image spans 100% of the viewport width.
- `50vw`: On desktop, the image spans 50% width in a 2-column grid.

With `sizes`, Next.js serves a **30KB 400px image to mobile phones** and a **150KB 1200px image to 4K desktop screens**.

---

## 3. Third-Party Script Optimization with `next/script`

Loading third-party scripts (Google Analytics, Stripe, HubSpot, Intercom) with standard `<script>` tags blocks page rendering and degrades performance.

**`next/script`** provides prioritized execution strategies:

```tsx
import Script from "next/script";

export function ThirdPartyIntegrations() {
  return (
    <>
      {/* 1. afterInteractive (Default): Loads immediately after the page becomes interactive (Ideal for Analytics) */}
      <Script
        src="https://www.googletagmanager.com/gtag/js?id=G-XXXXX"
        strategy="afterInteractive"
      />
      <Script id="google-analytics" strategy="afterInteractive">
        {`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', 'G-XXXXX');
        `}
      </Script>

      {/* 2. lazyOnload: Loads during browser idle time (Ideal for Chat widgets, support bots) */}
      <Script
        src="https://widget.intercom.io/widget/app_id"
        strategy="lazyOnload"
        onLoad={() => console.log("Intercom chat widget loaded")}
      />

      {/* 3. beforeInteractive: Loads in <head> BEFORE any Next.js code runs (Rare: Bot detection / polyfills) */}
      <Script
        src="https://security.bot-detection.com/sensor.js"
        strategy="beforeInteractive"
      />
    </>
  );
}
```

---

## Troubleshooting & Best Practices

1. **Remote Image Error: `Invalid src prop on next/image, hostname is not configured`**
   If you use remote image URLs (`https://s3.amazonaws.com/...`), you must whitelist the hostname in `next.config.ts` under `images.remotePatterns`.

2. **Always set `priority={true}` on the LCP Hero Image**
   The single largest image visible in the initial viewport (hero banner) should always have `priority={true}` to disable lazy loading and boost your Largest Contentful Paint score to <1.5s.
