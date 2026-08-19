# Module 14: Subprocess Management & OS Signals

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Process Control & System Integration

---

## Running External Commands with `Deno.Command`

`Deno.Command` is the modern Deno API (since 1.31) for spawning and managing subprocesses. It replaces the deprecated `Deno.run()`. It gives you fine-grained control over stdin, stdout, and stderr, and supports both synchronous (blocking) and asynchronous execution.

Subprocess creation requires `--allow-run` or `--allow-run=<command>` permission.

---

## Basic Command Execution

```typescript
// Simple: run a command and capture output
const command = new Deno.Command("git", {
  args: ["rev-parse", "HEAD"],
  stdout: "piped",
  stderr: "piped",
});

const { code, stdout, stderr } = await command.output();

if (code !== 0) {
  const errorText = new TextDecoder().decode(stderr);
  throw new Error(`git failed with code ${code}: ${errorText}`);
}

const commitHash = new TextDecoder().decode(stdout).trim();
console.log("Current commit:", commitHash);
```

---

## Output Capture Modes

```typescript
// stdout/stderr modes:
// "piped"  — capture output in memory (returned in .output())
// "inherit" — forward to parent process's stdout/stderr (visible in terminal)
// "null"   — discard output

// Show command output in the terminal (inherit)
const build = new Deno.Command("deno", {
  args: ["task", "build"],
  stdout: "inherit",
  stderr: "inherit",
});
const { code } = await build.output();
if (code !== 0) throw new Error("Build failed");

// Capture and parse command output
const psCommand = new Deno.Command("ps", {
  args: ["-ax", "-o", "pid,command"],
  stdout: "piped",
});
const psOutput = await psCommand.output();
const processes = new TextDecoder()
  .decode(psOutput.stdout)
  .split("\n")
  .filter((line) => line.includes("deno"));
console.log("Deno processes:", processes);

// Discard output entirely (fire and forget style)
const touch = new Deno.Command("touch", {
  args: ["./last-run.txt"],
  stdout: "null",
  stderr: "null",
});
await touch.output();
```

---

## Providing stdin Input

```typescript
// Pass data to a command via stdin
const encoder = new TextEncoder();

const grepCommand = new Deno.Command("grep", {
  args: ["ERROR"],
  stdin: "piped",
  stdout: "piped",
});

const child = grepCommand.spawn();

// Write to stdin
const logData = `INFO started\nERROR failed to connect\nINFO retrying\nERROR timeout\n`;
const writer = child.stdin.getWriter();
await writer.write(encoder.encode(logData));
await writer.close();

// Read stdout
const reader = child.stdout.getReader();
let result = "";
while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  result += new TextDecoder().decode(value);
}

const { code } = await child.status;
console.log("grep exit code:", code);
console.log("Matching lines:", result);
// ERROR failed to connect
// ERROR timeout
```

---

## Long-Running Child Processes

```typescript
// Spawn a child process and keep it running
const server = new Deno.Command("node", {
  args: ["./legacy-server.js"],
  stdout: "inherit",
  stderr: "inherit",
  env: {
    PORT: "4000",
    NODE_ENV: "production",
    // Spread parent environment variables
    ...Object.fromEntries(Object.entries(Deno.env.toObject())),
  },
}).spawn();

console.log(`Child server PID: ${server.pid}`);

// Wait for it to exit
const status = await server.status;
console.log(`Server exited with code: ${status.code}`);

// Kill the child process
server.kill("SIGTERM");
// or
server.kill("SIGKILL");  // Force kill if SIGTERM is ignored

// Check if the child has exited
const finalStatus = await server.status;
```

---

## Pipeline of Commands

```typescript
// Implement: ls -la | grep ".ts" | wc -l
// (equivalent to shell pipe)

async function pipeCommands(...commands: string[][]): Promise<string> {
  let input: ReadableStream<Uint8Array> | undefined;

  for (let i = 0; i < commands.length; i++) {
    const [cmd, ...args] = commands[i];
    const child = new Deno.Command(cmd, {
      args,
      stdin: i === 0 ? "null" : "piped",
      stdout: i === commands.length - 1 ? "piped" : "piped",
      stderr: "null",
    }).spawn();

    if (input && child.stdin) {
      input.pipeTo(child.stdin);
    }
    input = child.stdout;
  }

  const reader = input!.getReader();
  let result = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    result += new TextDecoder().decode(value);
  }
  return result.trim();
}

const lineCount = await pipeCommands(
  ["ls", "-la"],
  ["grep", ".ts"],
  ["wc", "-l"],
);
console.log(`TypeScript files: ${lineCount}`);
```

---

## Synchronous Commands

For scripts that must block until the command completes:

```typescript
// outputSync() blocks the event loop — use sparingly
const result = new Deno.Command("git", {
  args: ["status", "--porcelain"],
  stdout: "piped",
  stderr: "null",
}).outputSync();

const hasChanges = result.stdout.length > 0;
console.log("Has uncommitted changes:", hasChanges);
```

---

## OS Signal Handling

Deno allows your program to react to OS signals — `SIGTERM` for graceful shutdown, `SIGINT` for Ctrl+C, `SIGHUP` for configuration reload.

```typescript
// Graceful HTTP server shutdown on SIGTERM/SIGINT

const kv = await Deno.openKv();

// Server state
let isShuttingDown = false;
let activeRequests = 0;

const server = Deno.serve({
  port: 8080,
  onListen({ port }) {
    console.log(`Server listening on :${port}`);
  },
}, async (req) => {
  if (isShuttingDown) {
    return new Response("Service Unavailable: shutting down", {
      status: 503,
      headers: { "Retry-After": "5" },
    });
  }

  activeRequests++;
  try {
    // Handle request
    await new Promise((r) => setTimeout(r, 100));  // Simulate processing
    return new Response("OK");
  } finally {
    activeRequests--;
  }
});

// Graceful shutdown handler
async function gracefulShutdown(signal: string): Promise<void> {
  console.log(`\nReceived ${signal}. Starting graceful shutdown...`);
  isShuttingDown = true;

  // Stop accepting new connections
  server.shutdown();

  // Wait for active requests to complete (up to 30 seconds)
  const deadline = Date.now() + 30_000;
  while (activeRequests > 0 && Date.now() < deadline) {
    console.log(`Waiting for ${activeRequests} active requests...`);
    await new Promise((r) => setTimeout(r, 500));
  }

  if (activeRequests > 0) {
    console.warn(`Force closing ${activeRequests} remaining connections`);
  }

  // Flush any pending KV writes
  kv.close();

  console.log("Shutdown complete");
  Deno.exit(0);
}

// Register signal handlers
Deno.addSignalListener("SIGTERM", () => gracefulShutdown("SIGTERM"));
Deno.addSignalListener("SIGINT",  () => gracefulShutdown("SIGINT"));

// On Unix: reload configuration on SIGHUP (not available on Windows)
if (Deno.build.os !== "windows") {
  Deno.addSignalListener("SIGHUP", async () => {
    console.log("SIGHUP received — reloading configuration");
    // Re-read config file, update in-memory state
    const config = JSON.parse(await Deno.readTextFile("./config.json"));
    updateConfig(config);
  });
}

function updateConfig(_config: unknown): void { /* apply config */ }
```

---

## Available Signals

| Signal | Typical Meaning | Available on Windows |
| --- | --- | --- |
| `SIGTERM` | Polite shutdown request | ❌ |
| `SIGINT` | Ctrl+C interrupt | ✅ |
| `SIGHUP` | Reload config | ❌ |
| `SIGUSR1` | User-defined | ❌ |
| `SIGUSR2` | User-defined | ❌ |
| `SIGALRM` | Timer alarm | ❌ |
| `SIGCHLD` | Child process changed | ❌ |

```typescript
// Remove a signal handler
const handler = () => console.log("Got SIGTERM");
Deno.addSignalListener("SIGTERM", handler);

// Later:
Deno.removeSignalListener("SIGTERM", handler);
```

---

## Process Information

```typescript
// Current process
console.log("PID:", Deno.pid);
console.log("Parent PID:", Deno.ppid);
console.log("OS:", Deno.build.os);
console.log("Architecture:", Deno.build.arch);
console.log("Deno version:", Deno.version.deno);
console.log("V8 version:", Deno.version.v8);
console.log("TypeScript version:", Deno.version.typescript);

// System memory
const memUsage = Deno.memoryUsage();
console.log("Heap used:", Math.round(memUsage.heapUsed / 1024 / 1024), "MB");
console.log("RSS:", Math.round(memUsage.rss / 1024 / 1024), "MB");

// CPU time
const cpuUsage = Deno.cpuUsage();
console.log("User CPU:", cpuUsage.user, "μs");
console.log("System CPU:", cpuUsage.system, "μs");

// Elapsed time since process start (milliseconds)
console.log("Uptime:", performance.now(), "ms");
```

---

## Troubleshooting

### `PermissionDenied: Requires run access to "git"`

Add `--allow-run=git` to your command. To allow a specific set of commands: `--allow-run=git,deno,node`. To allow all commands: `--allow-run`.

### `Deno.Command` child process hangs indefinitely

The child process is waiting for stdin input. Set `stdin: "null"` if the command doesn't need input, or close the stdin writer after sending data.

### Signal handlers not called on Ctrl+C

If you're using `--no-check` or running in a non-interactive mode, signals may behave differently. Ensure you're adding the listener before any `await` that might keep the process alive differently. Also note: `SIGINT` is always available; other signals require a Unix-like OS.
