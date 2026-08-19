# Module 12: Styling Solutions — Tailwind CSS, CSS Modules & Design Tokens

**Track:** Next.js — Full-Stack App Router & Edge Architecture
**Category:** Styling Solutions, Design Systems & CSS Architecture

---

## 1. The Styling Landscape in the App Router & Server Components

The introduction of React Server Components (RSC) fundamentally changed styling recommendations for React applications:

| Styling Paradigm | Compatible with Server Components? | Runtime Performance | Key Advantages |
| :--- | :--- | :--- | :--- |
| **Tailwind CSS** | **100% Native** | **Zero Runtime** (Pure static CSS) | Ultra-fast development, tiny purged production CSS |
| **CSS Modules (`.module.css`)** | **100% Native** | **Zero Runtime** (Pure static CSS) | Scoped classes, zero naming collisions, standard CSS syntax |
| **Vanilla CSS & CSS Variables** | **100% Native** | **Zero Runtime** | Built-in browser theming, design tokens |
| **Runtime CSS-in-JS (styled-components)** | **Requires `'use client'`** | **High JS Runtime Overhead** | Legacy dynamic style evaluation |

Because Server Components execute strictly on the server and do not ship runtime JavaScript to the client, **Zero-Runtime styling solutions (Tailwind CSS, CSS Modules, CSS Variables)** are the gold standard for Next.js.

---

## 2. Setting Up Tailwind CSS with Design Tokens

```bash
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

### 1. Enterprise Tailwind Configuration (`tailwind.config.ts`)

```typescript
// tailwind.config.ts
import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class", '[data-theme="dark"]'], // Class & attribute dark mode support
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // Semantic design token mappings backed by CSS Custom Properties
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        border: "hsl(var(--border))",
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
    },
  },
  plugins: [],
};

export default config;
```

---

## 3. Global CSS & Design Tokens (`src/app/globals.css`)

```css
/* src/app/globals.css */
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    --primary: 221.2 83.2% 53.3%;
    --primary-foreground: 210 40% 98%;
    --muted: 210 40% 96.1%;
    --muted-foreground: 215.4 16.3% 46.9%;
    --border: 214.3 31.8% 91.4%;
    --radius: 0.5rem;
  }

  [data-theme="dark"],
  .dark {
    --background: 222.2 84% 4.9%;
    --foreground: 210 40% 98%;
    --primary: 217.2 91.2% 59.8%;
    --primary-foreground: 222.2 47.4% 11.2%;
    --muted: 217.2 32.6% 17.5%;
    --muted-foreground: 215 20.2% 65.1%;
    --border: 217.2 32.6% 17.5%;
  }

  body {
    background-color: hsl(var(--background));
    color: hsl(var(--foreground));
    font-feature-settings: "rlig" 1, "calt" 1;
  }
}
```

---

## 4. CSS Modules (`*.module.css`) for Component Scoping

CSS Modules automatically hash class names (e.g. `.button` becomes `.Button_button__a8f9z`) to guarantee zero naming collisions:

```css
/* src/components/Badge.module.css */
.badge {
  display: inline-flex;
  align-items: center;
  padding: 0.25rem 0.75rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
}

.primary {
  background-color: #3b82f6;
  color: #ffffff;
}

.success {
  background-color: #10b981;
  color: #ffffff;
}

.warning {
  background-color: #f59e0b;
  color: #ffffff;
}
```

```tsx
// src/components/Badge.tsx (Server Component compatible!)
import styles from "./Badge.module.css";

export function Badge({
  label,
  variant = "primary",
}: {
  label: string;
  variant?: "primary" | "success" | "warning";
}) {
  return (
    <span className={`${styles.badge} ${styles[variant]}`}>
      {label}
    </span>
  );
}
```

---

## 5. Class Merging Utility (`clsx` & `tailwind-merge`)

When building polymorphic UI components with conditional classes and prop overrides, class conflicts can occur (e.g. `bg-red-500` conflicting with `bg-blue-500`).

Use the industry standard **`cn()`** helper:

```bash
npm install clsx tailwind-merge
```

```typescript
// src/lib/utils.ts
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

```tsx
// src/components/Button.tsx
import { cn } from "@/lib/utils";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "destructive" | "outline";
}

export function Button({ className, variant = "default", ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center rounded-md font-medium transition-colors focus-visible:outline-none disabled:opacity-50",
        variant === "default" && "bg-primary text-primary-foreground hover:bg-primary/90",
        variant === "destructive" && "bg-red-600 text-white hover:bg-red-700",
        variant === "outline" && "border border-border bg-transparent hover:bg-muted",
        className // Caller can safely override classes without conflicts!
      )}
      {...props}
    />
  );
}
```

---

## Troubleshooting & Best Practices

1. **Dynamic Tailwind Class Names Anti-Pattern**
   Tailwind uses a build-time regex scanner. Constructing dynamic class strings like `className={`bg-${color}-500`}` will fail because Tailwind does not know which color classes to generate in the output CSS. Always use full class names in lookup objects:

   ```typescript
   const COLOR_MAP = {
     red: "bg-red-500",
     blue: "bg-blue-500",
     green: "bg-green-500",
   };
   ```
