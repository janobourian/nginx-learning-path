# Module 18: Enterprise Security Hardening, ReDoS Defense & Rate Limiting

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture
**Category:** Application Security, Rate Limiting & ReDoS Elimination

---

## 1. The Enterprise Security Defense Matrix

```text
┌─────────────────────────────────────────────────────────────┐
│                 Backend Security Threat Matrix              │
├────────────────────┬────────────────────────────────────────┤
│ **1. ReDoS**       │ Catastrophic backtracking in regexes   │
│                    │ that locks 100% of CPU for minutes.    │
├────────────────────┼────────────────────────────────────────┤
│ **2. Injection**   │ SQL, NoSQL & Shell command injection.  │
├────────────────────┼────────────────────────────────────────┤
│ **3. Brute Force** │ API key & password enumeration.        │
│                    │ ──► **Defense: Token Bucket Limiter**  │
├────────────────────┼────────────────────────────────────────┤
│ **4. SSRF** (Server│ Malicious internal metadata/network    │
│ Side Request Forg.)│ probing (`169.254.169.254`).           │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Eliminating Regular Expression Denial of Service (ReDoS)

A **ReDoS vulnerability** occurs when a regex contains nested quantifiers with overlapping capture groups (e.g. `(a+)+$`).

When evaluated against a string of 30 "a" characters ending in an exclamation mark, V8's regex backtracking engine executes **$2^{30}$ calculations, completely freezing the entire Node.js / Deno event loop for over 5 minutes!**

### Dangerous vs Safe Regex Comparison

```javascript
// ❌ CRITICAL REDOS VULNERABILITY (Exponential Backtracking O(2^N)):
const dangerousRegex = /^([a-zA-Z0-9_.-]+)+@([a-zA-Z0-9_.-]+)+\.([a-zA-Z]+)$/;

// ✅ SAFE REGEX (Linear Matching O(N)):
const safeEmailRegex = /^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$/;
```

---

## 3. Distributed Token Bucket Rate Limiter with Redis

The **Token Bucket Algorithm** allows bursts of traffic while enforcing a strict steady-state rate:

```javascript
// src/security/token_bucket.js
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);

/**

 * Token Bucket Rate Limiter:
 * - Max Capacity: 100 tokens
 * - Refill Rate: 10 tokens per second
 */
export async function consumeToken(clientId, capacity = 100, refillRatePerSec = 10) {
  const key = `ratelimit:token_bucket:${clientId}`;
  const now = Date.now() / 1000; // Seconds

  // Atomic Lua Script executing inside Redis engine:
  const luaScript = `
    local key = KEYS[1]
    local capacity = tonumber(ARGV[1])
    local refillRate = tonumber(ARGV[2])
    local now = tonumber(ARGV[3])

    local data = redis.call("HMGET", key, "tokens", "lastUpdated")
    local tokens = tonumber(data[1])
    local lastUpdated = tonumber(data[2])

    if not tokens then
      tokens = capacity
      lastUpdated = now
    else
      local delta = math.max(0, now - lastUpdated)
      tokens = math.min(capacity, tokens + delta * refillRate)
      lastUpdated = now
    end

    if tokens >= 1 then
      tokens = tokens - 1
      redis.call("HMSET", key, "tokens", tokens, "lastUpdated", lastUpdated)
      redis.call("EXPIRE", key, math.ceil(capacity / refillRate))
      return { 1, math.floor(tokens) } -- Allowed
    else
      return { 0, 0 } -- Rate limited!
    end
  `;

  const [allowed, remainingTokens] = await redis.eval(
    luaScript, 1, key, capacity, refillRatePerSec, now
  );

  return {
    isAllowed: allowed === 1,
    remainingTokens,
  };
}
```

---

## 4. Server-Side Request Forgery (SSRF) Defense

When an API fetches an external user-provided URL (e.g. fetching a user's webhook or avatar image), attackers may pass internal cloud metadata endpoints (`http://169.254.169.254/latest/meta-data/`) to steal AWS IAM credentials:

```javascript
// src/security/ssrf_filter.js
import dns from 'node:dns/promises';
import ipaddr from 'ipaddr.js';

export async function validateSafeExternalUrl(rawUrlString) {
  const url = new URL(rawUrlString);

  // 1. Enforce HTTPS only:
  if (url.protocol !== 'https:') {
    throw new Error('Only HTTPS protocols are permitted.');
  }

  // 2. Resolve DNS IP addresses:
  const addresses = await dns.resolve4(url.hostname);

  for (const ip of addresses) {
    const parsedIp = ipaddr.parse(ip);
    const range = parsedIp.range();

    // 3. Block private / loopback / link-local / cloud metadata ranges:
    if (
      range === 'private' ||
      range === 'loopback' ||
      range === 'linkLocal' ||
      ip === '169.254.169.254'
    ) {
      throw new Error(`SSRF Blocked: Destination IP ${ip} is a private internal network address.`);
    }
  }

  return url.toString();
}
```

---

## Troubleshooting & Best Practices

1. **Test Regular Expressions for ReDoS**
   Use tools like `vuln-regex-detector` in your CI pipeline to identify exponential backtracking vulnerabilities before deploying to production.

2. **Set Hard Limits on Request Body Size**
   Always configure maximum payload sizes (`express.json({ limit: '100kb' })`) to prevent attackers from sending 50MB JSON bodies that crash the JSON parser.
