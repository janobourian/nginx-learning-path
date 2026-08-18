# Module 12: File System I/O & Streams

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** File Operations & Data Streaming

---

## The Two I/O APIs in Deno

Deno provides two levels of file system access:

**The `Deno` namespace** — low-level APIs that mirror OS syscalls closely: `Deno.open()`, `Deno.readFile()`, `Deno.writeFile()`, `Deno.stat()`. These are Deno-specific and give you maximum control.

**The Web Streams API** — the same `ReadableStream`, `WritableStream`, and `TransformStream` interfaces browsers use. These are chainable, composable, and work the same in Deno as in browser Service Workers. They are the recommended way to handle large files and streaming data.

Both work together: `Deno.open()` returns a file object whose `.readable` property is a `ReadableStream` and `.writable` is a `WritableStream`.

---

## Reading Files

```typescript
// ── Simple reads (small files that fit in memory) ─────────────────────────

// Read entire file as a string (UTF-8)
const text = await Deno.readTextFile("./config.json");
const config = JSON.parse(text);

// Read entire file as raw bytes
const bytes = await Deno.readFile("./image.png");  // Returns Uint8Array
console.log(`Image size: ${bytes.length} bytes`);

// Read lines of a text file (standard library)
import { readLines } from "@std/io";
const file = await Deno.open("./large-dataset.csv");
try {
  for await (const line of readLines(file)) {
    // Process one line at a time — memory efficient
    const [id, name, email] = line.split(",");
    console.log({ id, name, email });
  }
} finally {
  file.close();
}

// ── Low-level reads (maximum control) ─────────────────────────────────────

const file2 = await Deno.open("./binary.dat", { read: true });
const buffer = new Uint8Array(4096);   // 4KB read buffer

let totalBytesRead = 0;
let bytesRead: number | null;

while ((bytesRead = await file2.read(buffer)) !== null) {
  // Process buffer[0..bytesRead]
  totalBytesRead += bytesRead;
}

file2.close();
console.log(`Read ${totalBytesRead} bytes`);
```

---

## Writing Files

```typescript
// ── Simple writes ──────────────────────────────────────────────────────────

// Write a string (overwrites existing file)
await Deno.writeTextFile("./output.txt", "Hello, Deno!\n");

// Append to a file
await Deno.writeTextFile("./log.txt", `${new Date().toISOString()} INFO started\n`, {
  append: true,
});

// Write binary data
const header = new Uint8Array([0x89, 0x50, 0x4E, 0x47]);  // PNG magic bytes
await Deno.writeFile("./output.png", header);

// ── Low-level writes ───────────────────────────────────────────────────────

const outputFile = await Deno.open("./output.bin", {
  write: true,
  create: true,
  truncate: true,   // Start fresh
});

const encoder = new TextEncoder();
await outputFile.write(encoder.encode("line 1\n"));
await outputFile.write(encoder.encode("line 2\n"));

// Seek to a specific byte offset before writing
await outputFile.seek(0, Deno.SeekMode.Start);
await outputFile.write(encoder.encode("UPDATED"));

outputFile.close();

// ── Using the Explicit Resource Management proposal (Deno 2+) ───────────────
// 'using' automatically calls .close() at end of scope
{
  using file = await Deno.open("./data.txt", { write: true, create: true });
  await file.write(encoder.encode("data\n"));
}  // file.close() called automatically here
```

---

## Streaming Large Files with Web Streams

The Web Streams API is the right tool for files larger than available memory — process data as it arrives without loading it all at once:

```typescript
// ── Stream a large file through a transformation ───────────────────────────

// Example: count words in a 10GB log file without loading it into memory
async function countWords(filePath: string): Promise<number> {
  const file = await Deno.open(filePath, { read: true });
  let wordCount = 0;

  await file.readable
    .pipeThrough(new TextDecoderStream())          // bytes → string chunks
    .pipeThrough(new TransformStream<string, string>({
      transform(chunk, controller) {
        // Count words in each chunk
        const words = chunk.match(/\b\w+\b/g);
        if (words) wordCount += words.length;
        controller.enqueue(chunk);
      },
    }))
    .pipeTo(new WritableStream({ write() {} }));   // Consume the stream

  return wordCount;
}

// ── Pipe a file to an HTTP response ───────────────────────────────────────

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const filePath = `./public${url.pathname}`;

  try {
    const stat = await Deno.stat(filePath);
    const file = await Deno.open(filePath, { read: true });

    return new Response(file.readable, {
      headers: {
        "Content-Type": getContentType(filePath),
        "Content-Length": stat.size.toString(),
        "Cache-Control": "public, max-age=3600",
      },
    });
  } catch {
    return new Response("Not Found", { status: 404 });
  }
});

function getContentType(path: string): string {
  if (path.endsWith(".html")) return "text/html";
  if (path.endsWith(".js")) return "application/javascript";
  if (path.endsWith(".css")) return "text/css";
  if (path.endsWith(".png")) return "image/png";
  if (path.endsWith(".jpg")) return "image/jpeg";
  return "application/octet-stream";
}
```

---

## TransformStream: Composable Data Pipelines

`TransformStream` creates a duplex: data enters the writable side, gets transformed, and exits the readable side. Chain multiple transforms into a pipeline:

```typescript
// ── CSV parsing pipeline ───────────────────────────────────────────────────

class CSVParseStream extends TransformStream<string, Record<string, string>> {
  constructor(headers?: string[]) {
    let headerRow: string[] | undefined = headers;
    super({
      transform(chunk, controller) {
        // Handle multiple lines per chunk
        const lines = chunk.split("\n").filter((l) => l.trim());
        for (const line of lines) {
          if (!headerRow) {
            headerRow = line.split(",").map((h) => h.trim());
            continue;
          }
          const values = line.split(",");
          const row: Record<string, string> = {};
          headerRow.forEach((key, i) => {
            row[key] = (values[i] ?? "").trim();
          });
          controller.enqueue(row);
        }
      },
    });
  }
}

// Use the pipeline
async function processCSV(inputPath: string, outputPath: string): Promise<void> {
  const input = await Deno.open(inputPath, { read: true });
  const output = await Deno.open(outputPath, { write: true, create: true, truncate: true });

  let processedRows = 0;

  await input.readable
    .pipeThrough(new TextDecoderStream())         // Uint8Array → string
    .pipeThrough(new CSVParseStream())             // string → Record<string, string>
    .pipeThrough(new TransformStream({             // Filter rows
      transform(row, controller) {
        if (Number(row.age) >= 18) controller.enqueue(row);
      },
    }))
    .pipeThrough(new TransformStream({             // Convert back to CSV
      transform(row, controller) {
        processedRows++;
        controller.enqueue(new TextEncoder().encode(
          Object.values(row).join(",") + "\n"
        ));
      },
    }))
    .pipeTo(output.writable);

  console.log(`Processed ${processedRows} rows`);
}

await processCSV("./users.csv", "./adults.csv");
```

---

## Directory Operations

```typescript
import { exists, ensureDir, walk, expandGlob } from "@std/fs";
import { join, relative } from "@std/path";

// Check existence
const fileExists = await exists("./config.json");
const dirExists = await exists("./logs", { isDirectory: true });

// Create nested directories
await ensureDir("./data/cache/thumbnails");

// List directory contents
for await (const entry of Deno.readDir("./src")) {
  if (entry.isFile && entry.name.endsWith(".ts")) {
    console.log(entry.name);
  }
}

// Walk directory recursively
const allTsFiles: string[] = [];
for await (const entry of walk("./src", {
  exts: [".ts"],
  skip: [/node_modules/, /__tests__/],
  includeDirs: false,
})) {
  allTsFiles.push(entry.path);
}
console.log(`Found ${allTsFiles.length} TypeScript files`);

// Glob patterns
for await (const file of expandGlob("**/*.{ts,tsx}", {
  root: "./src",
  exclude: ["**/*.test.ts"],
})) {
  console.log(relative("./src", file.path));
}

// File metadata
const stat = await Deno.stat("./large-file.bin");
console.log({
  size: stat.size,
  created: stat.birthtime,
  modified: stat.mtime,
  isFile: stat.isFile,
  isDirectory: stat.isDirectory,
  isSymlink: stat.isSymlink,
});
```

---

## Watching Files for Changes

```typescript
// Watch a directory for changes (e.g., hot reload)
const watcher = Deno.watchFs("./src", { recursive: true });

for await (const event of watcher) {
  console.log(`${event.kind}: ${event.paths.join(", ")}`);
  // event.kind: "create" | "modify" | "remove" | "access" | "any"
}
```

---

## Temporary Files and Directories

```typescript
// Create a temporary file
const tempFile = await Deno.makeTempFile({
  prefix: "upload_",
  suffix: ".tmp",
  dir: "/tmp",  // Optional: specify location
});

try {
  await Deno.writeTextFile(tempFile, "temporary data");
  // ... process the file
} finally {
  await Deno.remove(tempFile);
}

// Create a temporary directory
const tempDir = await Deno.makeTempDir({ prefix: "extract_" });
try {
  // ... use the directory
} finally {
  await Deno.remove(tempDir, { recursive: true });
}
```

---

## Troubleshooting

**`PermissionDenied: Requires read access to "/path/to/file"`**

Add `--allow-read=/path/to/file` or `--allow-read=/path/to/directory` to your run command. The path must match exactly or be a parent of the accessed path.

**Reading a large file causes OOM (out of memory)**

Replace `Deno.readFile()` / `Deno.readTextFile()` (which load the full file into memory) with streaming via `Deno.open()` and `file.readable`. Stream data through `TransformStream` processors rather than accumulating it.

**`file.read()` returns `null` prematurely**

`file.read()` returns `null` when the file is exhausted (EOF), not when the buffer is full. The return value is the number of bytes actually read (may be less than `buffer.length`). Only process `buffer[0..bytesRead]`, not the entire buffer.
