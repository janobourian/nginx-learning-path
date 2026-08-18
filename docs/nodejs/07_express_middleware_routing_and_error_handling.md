# Module 07: Express.js Architecture, Middleware Pipelines & Error Handling

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Web Frameworks, Middleware Architecture & Error Handling

---

## 1. The Express.js Middleware Pipeline

**Express.js** is the most widely adopted minimal web framework in the Node.js ecosystem. Its architecture is modeled as a **Sequential Middleware Chain (Chain of Responsibility Pattern)**:

```
Express Middleware Pipeline:
[Incoming Request]
        │
        ▼
[1. Request Logging Middleware (Pino/Morgan)]
        │ (next())
        ▼
[2. Security Headers Middleware (Helmet)]
        │ (next())
        ▼
[3. JSON Body Parser Middleware (express.json)]
        │ (next())
        ▼
[4. Authentication & JWT Guard]
        │ (next())
        ▼
[5. Route Handler (Controller)] ──► res.json({ success: true })
        │ (If error occurs: next(err))
        ▼
[6. Centralized Error Handling Middleware (4 Arguments: err, req, res, next)]
```

---

## 2. Setting Up an Enterprise Express Application

```bash
npm install express helmet cors express-rate-limit pino pino-http zod
```

### 1. Modular Router Architecture (`src/routes/users.router.js`)

```javascript
// src/routes/users.router.js
import { Router } from 'express';
import { z } from 'zod';

export const usersRouter = Router();

const CreateUserSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  role: z.enum(['admin', 'member']).default('member'),
});

// GET /api/v1/users/:id
usersRouter.get('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;
    if (id === '404') {
      const error = new Error('User not found in system');
      error.statusCode = 404;
      throw error;
    }

    res.json({
      id,
      name: 'Alice Chen',
      email: 'alice@acme.com',
    });
  } catch (err) {
    next(err); // Forward exception to Centralized Error Handler!
  }
});

// POST /api/v1/users
usersRouter.post('/', async (req, res, next) => {
  try {
    const validated = CreateUserSchema.parse(req.body);
    res.status(201).json({
      success: true,
      data: { id: `u_${Date.now()}`, ...validated },
    });
  } catch (err) {
    next(err);
  }
});
```

---

## 3. Centralized Asynchronous Error Handler

In Express, an **Error Handling Middleware** is uniquely identified by accepting **exactly 4 parameters: `(err, req, res, next)`**:

```javascript
// src/middleware/error_handler.js
import { ZodError } from 'zod';

export function centralizedErrorHandler(err, req, res, next) {
  const statusCode = err.statusCode || (err instanceof ZodError ? 400 : 500);

  // Structured Logging of Error:
  console.error(`[HTTP Error ${statusCode}] on ${req.method} ${req.url}:`, err.message);

  if (err instanceof ZodError) {
    res.status(400).json({
      error: 'Validation Error',
      details: err.flatten().fieldErrors,
    });
    return;
  }

  res.status(statusCode).json({
    error: err.name || 'InternalServerError',
    message: statusCode === 500 && process.env.NODE_ENV === 'production'
      ? 'An unexpected error occurred on the server.'
      : err.message,
    timestamp: new Date().toISOString(),
  });
}
```

---

## 4. Master Application Setup (`src/app.js`)

```javascript
// src/app.js
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { usersRouter } from './routes/users.router.js';
import { centralizedErrorHandler } from './middleware/error_handler.js';

export const app = express();

// 1. Security Headers:
app.use(helmet());

// 2. CORS Policy:
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
}));

// 3. Global Rate Limiter:
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per window
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api', limiter);

// 4. Request Body Parsing:
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// 5. Mount Feature Routers:
app.use('/api/v1/users', usersRouter);

// 6. 404 Catch-All Handler:
app.use((req, res, next) => {
  res.status(404).json({ error: 'Route not found' });
});

// 7. Centralized Error Handler (MUST BE LAST!):
app.use(centralizedErrorHandler);
```

---

## 5. Async Handler Wrapper (`express-async-errors`)

In Express 4, unhandled promise rejections inside `async` route handlers do not automatically reach error middleware unless caught and forwarded via `next(err)`.

Use an **`asyncHandler`** utility:

```javascript
export const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};

// Usage:
usersRouter.get('/profile', asyncHandler(async (req, res) => {
  const profile = await db.fetchProfile(); // Any rejected promise goes straight to error handler!
  res.json(profile);
}));
```

---

## Troubleshooting & Best Practices

1. **Error Handler Parameter Count Gotcha**
   If you declare `(err, req, res)` with only 3 parameters instead of `(err, req, res, next)`, Express will treat it as a standard request middleware and fail to catch errors! Always declare all 4 parameters.

2. **Always Place Error Handlers at the VERY BOTTOM**
   Express executes middleware in declaration order. If you register routes *after* `app.use(errorHandler)`, errors thrown by those routes will bypass the handler.
