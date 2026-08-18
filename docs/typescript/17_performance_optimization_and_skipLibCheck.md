# Module 17: Performance Optimization, Compiler Profiling & `skipLibCheck`

**Track:** TypeScript — Enterprise Type System  
**Category:** Compiler Optimization & Large Codebase Diagnostics

---

## 1. Why Does TypeScript Compilation Slow Down?

In enterprise codebases with hundreds of thousands of lines of code and hundreds of npm dependencies, `tsc` compilation and IDE type-checking can degrade from sub-second responses to 30+ second freezes.

The primary culprits of compiler slowdown:
1. **Redundant Type Checking of Third-Party Dependencies (`node_modules`)**: Checking external `.d.ts` declaration files that have already been validated by package authors.
2. **Pathological Generic Types**: Recursive conditional types or Cartesian template literal unions that explode combinatorial complexity.
3. **Massive Non-Discriminated Unions**: Computing union intersections and assignability across large un-tagged object unions ($O(N^2)$ checks).
4. **Missing Incremental Build Caches**: Re-checking the entire AST on every single line edit.

---

## 2. Profiling the Compiler: `--diagnostics` & `--generateTrace`

Before applying optimizations blindly, profile your compiler to identify where time and memory are being spent.

### 1. High-Level Diagnostics (`--diagnostics` & `--extendedDiagnostics`)

```bash
npx tsc --noEmit --extendedDiagnostics
```

Sample Diagnostic Output:
```
Files:                         1,420
Lines of Library:            145,210
Lines of Definitions:        380,450
Lines of TypeScript:          95,200
Nodes:                       850,300
Identifiers:                 320,100
Symbols:                     410,200
Types:                       125,400
Memory used:                 620 MB
I/O Read time:                 0.18s
Parse time:                    0.65s
Bind time:                     0.32s
Check time:                    8.45s  ◄── 80%+ of time spent in Check phase!
Total time:                    9.60s
```

If **Check time** is disproportionately large, pathological types or excess declaration checks are occurring.

### 2. Deep CPU Tracing (`--generateTrace`)

Generate Chromium-compatible performance trace files:

```bash
npx tsc --noEmit --generateTrace ./tsc-trace
```

This generates `trace.json` and `types.json`. 

### Analyzing the Trace:
1. Open Google Chrome and navigate to `chrome://tracing` (or `ui.perfetto.dev`).
2. Drag and drop `trace.json`.
3. Locate the widest horizontal blocks under `checkSourceFile` and `checkExpression` to see the exact file and line number causing compiler latency.
4. Run `@typescript/analyze-trace` to automatically highlight hot spots:
   ```bash
   npx @typescript/analyze-trace ./tsc-trace
   ```

---

## 3. High-Impact `tsconfig` Performance Flags

### 1. `skipLibCheck: true` (The 5x Speedup Flag)

By default, `tsc` type-checks **every single `.d.ts` file in your `node_modules` folder**. If you import `react`, `aws-sdk`, and `lodash`, `tsc` parses and type-checks all of their internal declaration files from scratch.

Setting `"skipLibCheck": true` tells TypeScript to **skip type checking of all `.d.ts` declaration files** and only check the `.ts` files authored in your project:

```json
{
  "compilerOptions": {
    "skipLibCheck": true /* Essential for all enterprise projects */
  }
}
```

*Result:* Build times typically drop by **60% to 85%**.

### 2. `incremental: true` & `.tsbuildinfo`

Enables caching of the compiler AST, resolved modules, and type-check results to disk:

```json
{
  "compilerOptions": {
    "incremental": true,
    "tsBuildInfoFile": "./node_modules/.cache/tsbuildinfo"
  }
}
```

Subsequent runs of `tsc` only check files that have been modified since the last build.

---

## 4. Anti-Patterns that Destroy Type-Checking Performance

### 1. Interface Inheritance (`extends`) vs Giant Intersections (`&`)

In TypeScript, **interfaces cache their computed property layout by name**, whereas intersection types (`&`) must be structurally computed every time they are evaluated:

```typescript
// ❌ SLOW: Giant intersection type (computed structurally on every check)
type HugeObject = BaseProps &
  AuditableProps &
  ThemeProps &
  PermissionProps & { customField: string };

// ✅ FAST: Interface with extends (cached in compiler symbol table)
interface HugeObject
  extends BaseProps,
    AuditableProps,
    ThemeProps,
    PermissionProps {
  customField: string;
}
```

### 2. Cartesian Union Explosions in Template Literals

```typescript
type Digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9";

// ❌ CATASTROPHIC: Creates 10 * 10 * 10 * 10 * 10 = 100,000 union members!
// type ZipCode = `${Digit}${Digit}${Digit}${Digit}${Digit}`; // Freezes the compiler!

// ✅ FAST: Use string with branded type & runtime regex validator (Module 13)
type ZipCode = Brand<string, "ZipCode">;
```

### 3. Non-Discriminated Large Unions

```typescript
// ❌ SLOW: Checking assignability across 50 un-tagged objects requires 50 x 50 structural comparisons
type Action =
  | { payload: string; metadata: number }
  | { payload: number; timestamp: Date }
  | { payload: boolean; user: string };

// ✅ FAST: Discriminated Union with literal tag (Constant-time O(1) comparison!)
type Action =
  | { type: "STRING_ACTION"; payload: string; metadata: number }
  | { type: "NUMBER_ACTION"; payload: number; timestamp: Date }
  | { type: "BOOLEAN_ACTION"; payload: boolean; user: string };
```

---

## 5. Performance Benchmark Summary

| Optimization Technique | Typical Build Time Reduction | Memory Usage Impact |
| :--- | :--- | :--- |
| **`skipLibCheck: true`** | **50% – 80% Faster** | Moderate Reduction |
| **`incremental: true` (Warm Build)** | **70% – 95% Faster** | Slight Disk Cache Overhead |
| **Project References (Monorepos)** | **60% – 90% Faster** | Major Peak Memory Reduction |
| **Interface `extends` over `&`** | **15% – 30% Faster** | High Memory Reduction |
| **Discriminated Unions** | **20% – 40% Faster** | Significant CPU Savings |

---

## Troubleshooting & Best Practices

1. **`JavaScript heap out of memory` during `tsc`**
   - For giant legacy codebases, increase Node's max heap: `NODE_OPTIONS="--max-old-space-size=8192" npx tsc`.
   - Then immediately profile with `--generateTrace` to find and fix the runaway generic recursion causing the memory leak.

2. **CI Type Checking**
   Always run `tsc --noEmit` in CI. Do not run `tsc` (with emit) if your bundler (Vite / esbuild / Webpack) is already generating the production JS bundle.
