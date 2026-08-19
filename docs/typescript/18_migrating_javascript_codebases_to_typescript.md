# Module 18: Migrating Legacy JavaScript Codebases to TypeScript

**Track:** TypeScript — Enterprise Type System
**Category:** Migration Strategy, JSDoc Typing & Refactoring Playbooks

---

## 1. The Migration Dilemma: Big Bang vs Incremental

Attempting a **"Big Bang" migration** (renaming all 5,000 `.js` files to `.ts` in a single branch and trying to fix 20,000 errors at once) is a guaranteed recipe for failure, merge conflicts, production downtime, and developer burnout.

The industry standard enterprise approach is an **Incremental 4-Phase Migration** where JavaScript and TypeScript coexist peacefully in the exact same codebase, and features continue shipping without interruption.

```text
Incremental Migration Roadmap:
┌───────────────────────────────┐
│ Phase 1: Toolchain Setup      │  allowJs: true, checkJs: false (Zero code changes)
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ Phase 2: JSDoc Type-Checking  │  checkJs: true, // @ts-check (Type check JS files without renaming)
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ Phase 3: Module-by-Module .ts │  Rename .js -> .ts starting from leaf utilities up to core
└──────────────┬────────────────┘
               ▼
┌───────────────────────────────┐
│ Phase 4: Strict Mode Lockdown │  strict: true, eradicate 'any', enforce CI type gates
└───────────────────────────────┘
```

---

## 2. Phase 1: Toolchain Setup & Coexistence

Configure `tsconfig.json` so the TypeScript compiler accepts both JavaScript and TypeScript files side by side without throwing errors on existing JS files:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist",

    /* ─── Migration Flags ─── */
    "allowJs": true,           /* Allow JavaScript files to be imported and compiled */
    "checkJs": false,          /* Do not report errors in .js files yet */
    "strict": false,           /* Start non-strict, enable flags gradually */
    "noImplicitAny": false,    /* Allow implied 'any' initially */
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```

---

## 3. Phase 2: Typing JavaScript with JSDoc (`checkJs: true`)

Before renaming files to `.ts`, you can type-check existing JavaScript files using standard **JSDoc comments**:

```javascript
// src/services/legacyPayment.js
// @ts-check

/**

 * @typedef {Object} PaymentTransaction
 * @property {string} id
 * @property {number} amount
 * @property {'pending' | 'settled' | 'failed'} status
 */

/**

 * Charges a customer credit card.
 * @param {string} customerId - The unique customer identifier
 * @param {number} amountInCents - Positive amount in cents
 * @param {PaymentTransaction} [previousTx] - Optional previous transaction
 * @returns {Promise<PaymentTransaction>}
 */
export async function executeCharge(customerId, amountInCents, previousTx) {
  if (amountInCents <= 0) {
    throw new Error("Amount must be positive");
  }

  // TypeScript validates this JSDoc code and reports errors if types mismatch!
  return {
    id: `tx_${Date.now()}`,
    amount: amountInCents,
    status: "settled",
  };
}
```

---

## 4. Phase 3: Module-by-Module File Renaming Strategy

When converting `.js` files to `.ts`, follow a **Bottom-Up (Leaf to Root)** dependency order:

```text
Conversion Order:
1. Leaf Pure Utilities (e.g. `src/utils/math.js`, `src/utils/formatters.js`)
2. Data Models, Enums & Schemas (e.g. `src/models/*.js`)
3. Database & Network Clients (e.g. `src/db/client.js`)
4. Business Logic Services (e.g. `src/services/*.js`)
5. Controllers, API Endpoints & UI Components (e.g. `src/controllers/*.js`)
6. Entry Point (`src/index.js` -> `src/index.ts`)
```

### Automated Migration with `ts-migrate`

For large repositories, use Airbnb's open-source `ts-migrate` tool to automate file renaming, generate baseline `tsconfig.json` files, and automatically inject `// @ts-expect-error` comments on failing lines so your codebase compiles immediately:

```bash

# Install ts-migrate
npm install -g ts-migrate

# Run automated migration on source folder
npx ts-migrate rename src --sources "src/**/*.js"
npx ts-migrate init src
```

---

## 5. Phase 4: Strict Mode Lockdown & Eradicating `any`

Once all files are `.ts`, enable strict flags one by one in your `tsconfig.json` until full `strict: true` is achieved:

```text
Strict Flag Rollout Order:
1. "noImplicitThis": true
2. "alwaysStrict": true
3. "strictBindCallApply": true
4. "strictFunctionTypes": true
5. "strictPropertyInitialization": true
6. "noImplicitAny": true         ◄── The big milestone!
7. "strictNullChecks": true      ◄── The ultimate safety milestone!
8. "strict": true
```

### Eliminating Temporary `any` Types with ESLint

Configure `@typescript-eslint` rules to prevent developers from adding new `any` types or `@ts-ignore` comments:

```json
// .eslintrc.json
{
  "parser": "@typescript-eslint/parser",
  "plugins": ["@typescript-eslint"],
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/ban-ts-comment": [
      "error",
      {
        "ts-expect-error": "allow-with-description",
        "ts-ignore": true,
        "ts-nocheck": true
      }
    ],
    "@typescript-eslint/no-floating-promises": "error"
  }
}
```

---

## 6. Migration Metrics & Progress Tracking Script

Track migration progress in CI and post burndown metrics to Slack/Teams:

```typescript
// scripts/migration-progress.ts
import { glob } from "glob";

async function computeMigrationProgress() {
  const jsFiles = await glob("src/**/*.{js,jsx}");
  const tsFiles = await glob("src/**/*.{ts,tsx}");

  const total = jsFiles.length + tsFiles.length;
  const percentage = ((tsFiles.length / total) * 100).toFixed(1);

  console.log(`\n📊 TypeScript Migration Progress:`);
  console.log(`================================`);
  console.log(`TypeScript files: ${tsFiles.length}`);
  console.log(`JavaScript files: ${jsFiles.length}`);
  console.log(`Total files:      ${total}`);
  console.log(`Progress:         ${percentage}% Completed\n`);
}

computeMigrationProgress();
```

---

## Troubleshooting & Migration Gotchas

1. **Circular Dependencies in Legacy Code**
   Legacy JavaScript codebases often have circular `require()` calls that worked at runtime because of object mutation. In TypeScript, circular imports can cause type resolution errors. Break circularity by extracting shared interfaces into a separate `types.ts` leaf module.

2. **Dynamic Property Injection**
   In legacy JavaScript: `req.user = user;`. In TypeScript, use Module Augmentation (`declare module 'express' { ... }`) to declare injected properties cleanly (Module 10).
