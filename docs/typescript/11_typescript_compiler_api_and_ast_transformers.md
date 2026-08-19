# Module 11: TypeScript Compiler API & AST Transformers

**Track:** TypeScript — Enterprise Type System
**Category:** Compiler Internals, Static Analysis & Codegen

---

## 1. What Is the TypeScript Compiler API?

The `typescript` npm package is not just a command-line binary (`tsc`); it exports a comprehensive JavaScript/TypeScript library containing the **entire TypeScript compiler frontend and type checker**.

By using the **Compiler API** (`import ts from "typescript"`), you can:

1. **Inspect and Query ASTs**: Parse any TypeScript code and analyze its structure.
2. **Execute Semantic Type Checking**: Query types, find references, and validate assignments programmatically.
3. **Write Custom AST Transformers**: Modify code during compilation (e.g., stripping `console.log`, injecting telemetry, compiling custom DSLs).
4. **Generate Code**: Emit formatted TypeScript or JavaScript programmatically with full type safety.

---

## 2. The Abstract Syntax Tree (AST) & `SyntaxKind`

Every element in a TypeScript program is represented as a node in an **Abstract Syntax Tree (AST)**. Each node has:

- A `kind` property (`ts.SyntaxKind` enum, e.g., `ts.SyntaxKind.FunctionDeclaration`, `ts.SyntaxKind.Identifier`, `ts.SyntaxKind.StringLiteral`).
- References to its child nodes (`node.getChildren()`, `ts.forEachChild`).
- Source code position offsets (`node.pos`, `node.end`).

```text
Source Code: const total = price * 1.08;

AST Representation:
VariableStatement (SyntaxKind.VariableStatement)
  └── VariableDeclarationList (SyntaxKind.VariableDeclarationList)
        └── VariableDeclaration (SyntaxKind.VariableDeclaration)
              ├── Identifier (name: "total")
              └── BinaryExpression (SyntaxKind.BinaryExpression, operator: "*")
                    ├── Identifier (name: "price")
                    └── NumericLiteral (text: "1.08")
```

---

## 3. Parsing Code and Traversing the AST

```typescript
import ts from "typescript";

const sourceCode = `
function calculateTax(amount: number, rate: number): number {
  console.log("Computing tax for amount:", amount);
  return amount * rate;
}
`;

// 1. Parse raw source string into an AST SourceFile
const sourceFile = ts.createSourceFile(
  "taxCalculator.ts",
  sourceCode,
  ts.ScriptTarget.ES2022,
  true /* setParentNodes */,
  ts.ScriptKind.TS
);

// 2. Recursive AST Walker
function inspectNode(node: ts.Node, depth = 0) {
  const indentation = "  ".repeat(depth);
  const kindName = ts.SyntaxKind[node.kind];

  console.log(`${indentation}Node: ${kindName} [${node.pos}..${node.end}]`);

  // Visit all direct child nodes
  ts.forEachChild(node, (child) => inspectNode(child, depth + 1));
}

inspectNode(sourceFile);
```

---

## 4. Programmatic Type Checking & Symbol Resolution

To query semantic type information (not just syntax), create a `ts.Program`:

```typescript
import ts from "typescript";

// Create an in-memory compiler program
const fileNames = ["src/models/user.ts"];
const compilerOptions: ts.CompilerOptions = {
  target: ts.ScriptTarget.ES2022,
  module: ts.ModuleKind.NodeNext,
  strict: true,
};

const program = ts.createProgram(fileNames, compilerOptions);
const typeChecker = program.getTypeChecker();
const sourceFile = program.getSourceFile(fileNames[0]!)!;

// Find all exported interfaces and extract their property names and types:
ts.forEachChild(sourceFile, (node) => {
  if (ts.isInterfaceDeclaration(node)) {
    const symbol = typeChecker.getSymbolAtLocation(node.name);
    if (symbol) {
      console.log(`\nInterface: ${symbol.getName()}`);

      const type = typeChecker.getDeclaredTypeOfSymbol(symbol);
      const properties = type.getProperties();

      for (const prop of properties) {
        const propType = typeChecker.getTypeOfSymbolAtLocation(prop, node);
        const propTypeString = typeChecker.typeToString(propType);
        console.log(`  • ${prop.getName()}: ${propTypeString}`);
      }
    }
  }
});
```

---

## 5. Custom AST Transformers

AST Transformers run during the emit phase. A transformer receives a `SourceFile`, walks the AST, and replaces, removes, or creates nodes.

### Production Transformer: Stripping `console.log` from Production Builds

```typescript
import ts from "typescript";

export function removeConsoleLogTransformer<T extends ts.Node>(
  context: ts.TransformationContext
): ts.Transformer<T> {
  const { factory } = context;

  function visit(node: ts.Node): ts.Node | undefined {
    // Check if node is an ExpressionStatement: console.log(...)
    if (ts.isExpressionStatement(node)) {
      const expr = node.expression;
      if (ts.isCallExpression(expr)) {
        const callee = expr.expression;
        // Check for PropertyAccessExpression: console.log
        if (
          ts.isPropertyAccessExpression(callee) &&
          ts.isIdentifier(callee.expression) &&
          callee.expression.text === "console" &&
          callee.name.text === "log"
        ) {
          // Return undefined to delete the entire statement from the AST!
          return undefined;
        }
      }
    }

    // Recursively visit all child nodes
    return ts.visitEachChild(node, visit, context);
  }

  return (rootNode: T) => ts.visitNode(rootNode, visit) as T;
}
```

### Running the Custom Transformer

```typescript
import ts from "typescript";

const inputCode = `
function processPayment(id: string) {
  console.log("Processing payment for:", id);
  const success = true;
  console.log("Payment status:", success);
  return success;
}
`;

const sourceFile = ts.createSourceFile(
  "payment.ts",
  inputCode,
  ts.ScriptTarget.ES2022,
  true
);

// Apply custom transformer
const result = ts.transform(sourceFile, [removeConsoleLogTransformer]);
const transformedSourceFile = result.transformed[0]!;

// Print transformed code back to string
const printer = ts.createPrinter({ newLine: ts.NewLineKind.LineFeed });
const outputCode = printer.printFile(transformedSourceFile);

console.log("--- Output Code (No console.log) ---");
console.log(outputCode);
// Result:
// function processPayment(id: string) {
//   const success = true;
//   return success;
// }
```

---

## 6. Building a Custom Static Analysis Linter Rule

Let's build a static analysis rule that detects **unhandled floating Promises** in codebases:

```typescript
import ts from "typescript";

export function detectFloatingPromises(program: ts.Program): string[] {
  const checker = program.getTypeChecker();
  const errors: string[] = [];

  for (const sourceFile of program.getSourceFiles()) {
    if (sourceFile.isDeclarationFile) continue;

    function checkNode(node: ts.Node) {
      if (ts.isExpressionStatement(node)) {
        const type = checker.getTypeAtLocation(node.expression);
        const typeString = checker.typeToString(type);

        // If an expression statement evaluates to a Promise without 'await' or '.catch()'
        if (typeString.startsWith("Promise<")) {
          const { line, character } = sourceFile.getLineAndCharacterOfPosition(node.getStart());
          errors.push(
            `${sourceFile.fileName}:${line + 1}:${character + 1} - Found floating un-awaited Promise: ${node.getText()}`
          );
        }
      }
      ts.forEachChild(node, checkNode);
    }

    checkNode(sourceFile);
  }

  return errors;
}
```

---

## Troubleshooting & Best Practices

1. **Always use `context.factory` for node creation**
   In modern TypeScript (v4.0+), deprecated constructor functions (`ts.createIdentifier`) have been replaced with `context.factory.createIdentifier()`.

2. **Immutable Transformation**
   Never mutate existing AST nodes in-place. Always return new replacement nodes created via `context.factory`.

3. **Compiler Performance**
   Creating a `ts.Program` is computationally heavy because it loads the standard library `lib.d.ts` files. Reuse the `Program` instance across checks rather than recreating it per file.
