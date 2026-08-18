# Module 05: Deno Queues & Cron Tasks

**Track:** Deno Secure Engine & Edge Runtime  
**Category:** Background Processing & Scheduled Jobs

---

## Background Work Without External Infrastructure

Production applications invariably need two things: the ability to defer work to the background (queues) and the ability to run recurring jobs on a schedule (cron). In Node.js this typically means adding BullMQ + Redis for queues and node-cron or a separate cron job runner for schedules. Each adds infrastructure dependencies, deployment complexity, and cost.

Deno KV includes both features natively. `Deno.Kv.enqueue()` adds items to a durable queue backed by the same storage as your KV data. `Deno.cron()` registers recurring tasks that run on a standard cron schedule. Neither requires a separate process, message broker, or external service.

On Deno Deploy, queues are processed reliably with at-least-once delivery even across edge node failures. Locally, the queue is backed by SQLite with the same durability guarantees.

---

## Deno Queues

### Basic Enqueue and Listen

```typescript
const kv = await Deno.openKv();

// Define the message shape
interface EmailJob {
  type: "email";
  to: string;
  subject: string;
  body: string;
}

interface ResizeJob {
  type: "image_resize";
  inputPath: string;
  outputPath: string;
  width: number;
  height: number;
}

type Job = EmailJob | ResizeJob;

// Producer: add a job to the queue
async function enqueueEmail(to: string, subject: string, body: string): Promise<void> {
  const job: EmailJob = { type: "email", to, subject, body };
  await kv.enqueue(job);
  console.log(`Queued email to ${to}`);
}

// Consumer: process jobs from the queue
kv.listenQueue(async (job: Job) => {
  switch (job.type) {
    case "email":
      await sendEmail(job.to, job.subject, job.body);
      console.log(`Sent email to ${job.to}`);
      break;
    case "image_resize":
      await resizeImage(job.inputPath, job.outputPath, job.width, job.height);
      console.log(`Resized image: ${job.inputPath}`);
      break;
    default:
      console.warn("Unknown job type:", (job as { type: string }).type);
  }
});

// Stub implementations
async function sendEmail(to: string, subject: string, body: string): Promise<void> {
  // In practice: call SendGrid, SES, Resend, etc.
  console.log(`[EMAIL] To: ${to} | Subject: ${subject}`);
}

async function resizeImage(
  input: string, output: string, w: number, h: number
): Promise<void> {
  // In practice: use FFI to libvips or call an image processing service
  console.log(`[RESIZE] ${input} → ${output} (${w}x${h})`);
}
```

### Delayed Delivery

```typescript
const kv = await Deno.openKv();

// Enqueue a job to run after 5 minutes
await kv.enqueue(
  { type: "send_reminder", userId: "user_123" },
  { delay: 5 * 60 * 1000 }   // milliseconds
);

// Enqueue a job to run after 24 hours
await kv.enqueue(
  { type: "trial_expiry_email", userId: "user_456" },
  { delay: 24 * 60 * 60 * 1000 }
);
```

### Dead Letter Queue Pattern

By default, if the `listenQueue` handler throws an error, Deno retries the job automatically with exponential backoff. To permanently capture failed jobs for investigation rather than retrying forever, write them to a "dead letter" KV namespace before re-throwing:

```typescript
const kv = await Deno.openKv();
const MAX_ATTEMPTS = 5;

interface JobWithMeta {
  payload: Job;
  attempts: number;
  lastError?: string;
}

kv.listenQueue(async (raw: JobWithMeta) => {
  const { payload, attempts = 0 } = raw;

  try {
    await processJob(payload);
  } catch (error) {
    const err = error instanceof Error ? error.message : String(error);
    const nextAttempts = attempts + 1;

    if (nextAttempts >= MAX_ATTEMPTS) {
      // Send to dead letter storage — stop retrying
      await kv.set(
        ["dead_letter", crypto.randomUUID()],
        { payload, attempts: nextAttempts, lastError: err, failedAt: new Date() }
      );
      console.error(`Job permanently failed after ${MAX_ATTEMPTS} attempts:`, err);
      return; // Don't throw — prevents infinite retry loop
    }

    // Re-enqueue with updated attempt count and exponential backoff delay
    const backoffMs = Math.min(1000 * Math.pow(2, nextAttempts), 60_000);
    await kv.enqueue(
      { payload, attempts: nextAttempts, lastError: err },
      { delay: backoffMs }
    );
    console.warn(`Job failed (attempt ${nextAttempts}/${MAX_ATTEMPTS}), retrying in ${backoffMs}ms`);
  }
});

async function processJob(job: Job): Promise<void> {
  // actual job processing
}
```

### Queue + KV Atomic: Transactional Enqueue

You can enqueue a job and update KV state atomically — either both happen or neither does:

```typescript
const kv = await Deno.openKv();

async function createOrder(userId: string, items: CartItem[]): Promise<string> {
  const orderId = crypto.randomUUID();
  const orderKey = ["orders", orderId];
  const order = {
    id: orderId,
    userId,
    items,
    status: "pending",
    createdAt: new Date(),
  };

  // Atomically: write the order to KV and enqueue a fulfillment job
  const result = await kv.atomic()
    .check({ key: orderKey, versionstamp: null })  // Ensure order doesn't already exist
    .set(orderKey, order)
    .enqueue({ type: "fulfill_order", orderId })
    .commit();

  if (!result.ok) {
    throw new Error("Order creation conflict");
  }

  return orderId;
}
```

---

## Deno Cron

`Deno.cron()` registers a function to run on a recurring schedule using standard cron expression syntax.

### Basic Cron Registration

```typescript
// Runs every minute
Deno.cron("heartbeat", "* * * * *", async () => {
  await fetch("https://healthchecks.io/ping/your-id");
});

// Runs every day at 2:30 AM UTC
Deno.cron("daily-report", "30 2 * * *", async () => {
  const report = await generateDailyReport();
  await emailReport("admin@example.com", report);
});

// Runs every hour on the hour
Deno.cron("hourly-cache-warm", "0 * * * *", async () => {
  await warmProductCatalogCache();
});

// Runs every weekday at 9 AM
Deno.cron("weekday-summary", "0 9 * * 1-5", async () => {
  await sendTeamSummary();
});

// Runs on the 1st of every month at midnight
Deno.cron("monthly-billing", "0 0 1 * *", async () => {
  await processMonthlyBilling();
});
```

### Cron Expression Reference

```
┌─────── minute      (0 - 59)
│ ┌───── hour        (0 - 23)
│ │ ┌─── day-of-month (1 - 31)
│ │ │ ┌─ month        (1 - 12)
│ │ │ │ ┌ day-of-week  (0 - 7, 0 and 7 are Sunday)
│ │ │ │ │
* * * * *

Examples:
*/5 * * * *       Every 5 minutes
0 */6 * * *       Every 6 hours
0 8 * * 1         Every Monday at 8:00 AM
0 0 * * *         Every day at midnight (00:00)
30 23 * * 5       Every Friday at 11:30 PM
0 9-17 * * 1-5   Every hour from 9-17 on weekdays
```

### Cron with Error Handling and Logging

```typescript
const kv = await Deno.openKv();

Deno.cron("cleanup-expired-sessions", "0 * * * *", async () => {
  const cronKey = ["cron_runs", "cleanup_expired_sessions"];
  const startTime = Date.now();
  let deletedCount = 0;

  try {
    // List all session keys with a cutoff time
    const cutoff = Date.now() - 24 * 60 * 60 * 1000; // 24 hours ago
    const sessions = kv.list<{ createdAt: number }>({ prefix: ["sessions"] });

    for await (const session of sessions) {
      if (session.value.createdAt < cutoff) {
        await kv.delete(session.key);
        deletedCount++;
      }
    }

    // Record successful run
    await kv.set(cronKey, {
      lastRun: new Date(),
      durationMs: Date.now() - startTime,
      deletedCount,
      status: "success",
    });

    console.log(`[CRON] cleanup-expired-sessions: deleted ${deletedCount} sessions`);
  } catch (error) {
    // Record failed run — don't let errors silently disappear
    await kv.set(cronKey, {
      lastRun: new Date(),
      durationMs: Date.now() - startTime,
      status: "error",
      error: error instanceof Error ? error.message : String(error),
    });

    console.error("[CRON] cleanup-expired-sessions failed:", error);
    // Don't re-throw — Deno.cron will continue scheduling future runs regardless
  }
});
```

### Complete Background Worker Application

```typescript
// worker.ts — runs as a separate process alongside the main API server

const kv = await Deno.openKv();

console.log("Background worker started");

// ── Cron Jobs ─────────────────────────────────────────────────────────────

Deno.cron("hourly-analytics", "0 * * * *", async () => {
  console.log("[CRON] Computing hourly analytics...");
  const events = await collectHourlyEvents(kv);
  await storeAnalyticsSummary(kv, events);
});

Deno.cron("daily-digest", "0 6 * * *", async () => {
  console.log("[CRON] Sending daily digest emails...");
  const subscribers = kv.list<User>({ prefix: ["subscribers"] });
  for await (const entry of subscribers) {
    if (entry.value.digestEnabled) {
      await kv.enqueue({
        type: "digest_email",
        userId: entry.value.id,
      });
    }
  }
});

Deno.cron("cleanup-temp-files", "30 3 * * *", async () => {
  console.log("[CRON] Cleaning temporary files...");
  await cleanTempFiles("/tmp/uploads");
});

// ── Queue Processor ────────────────────────────────────────────────────────

kv.listenQueue(async (job: { type: string; [key: string]: unknown }) => {
  const start = Date.now();
  console.log(`[QUEUE] Processing: ${job.type}`);

  try {
    switch (job.type) {
      case "digest_email":
        await sendDigestEmail(job.userId as string);
        break;
      case "welcome_email":
        await sendWelcomeEmail(job.email as string, job.name as string);
        break;
      case "export_data":
        await exportUserData(job.userId as string, job.format as string);
        break;
      default:
        console.warn(`Unknown job type: ${job.type}`);
    }
    console.log(`[QUEUE] Completed ${job.type} in ${Date.now() - start}ms`);
  } catch (error) {
    console.error(`[QUEUE] Failed ${job.type}:`, error);
    throw error; // Let Deno retry with backoff
  }
});

// Stub implementations
async function collectHourlyEvents(kv: Deno.Kv): Promise<unknown[]> { return []; }
async function storeAnalyticsSummary(kv: Deno.Kv, events: unknown[]): Promise<void> {}
async function sendDigestEmail(userId: string): Promise<void> {}
async function sendWelcomeEmail(email: string, name: string): Promise<void> {}
async function exportUserData(userId: string, format: string): Promise<void> {}
async function cleanTempFiles(dir: string): Promise<void> {}

interface User { id: string; digestEnabled: boolean; }
```

Run the worker:
```bash
deno run \
  --allow-net \
  --allow-read=./config.json \
  --allow-env=DATABASE_URL,SMTP_HOST \
  worker.ts
```

---

## Troubleshooting

**`Deno.cron is not a function` or `Deno.cron is not available`**

Cron requires `--unstable-cron` in Deno 1.x. In Deno 2, it is stable. Upgrade Deno or add the flag: `deno run --unstable-cron worker.ts`.

**Queue handler runs but jobs never appear**

The `kv.listenQueue()` call must be reached at startup and kept alive. If your program exits before a job arrives, no handler runs. Structure your worker to run indefinitely — Deno keeps the process alive as long as `listenQueue` is active.

**Cron runs overlap — previous invocation still running when next fires**

`Deno.cron` does not prevent concurrent invocations. Use a KV-based distributed lock:

```typescript
Deno.cron("long-job", "*/5 * * * *", async () => {
  const lockKey = ["cron_lock", "long_job"];
  const acquired = await kv.atomic()
    .check({ key: lockKey, versionstamp: null })
    .set(lockKey, true, { expireIn: 4 * 60 * 1000 })  // lock expires in 4min
    .commit();

  if (!acquired.ok) {
    console.log("Previous invocation still running, skipping.");
    return;
  }

  try {
    await doLongWork();
  } finally {
    await kv.delete(lockKey);
  }
});
```
