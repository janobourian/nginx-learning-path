# Module 15: Enterprise Authentication — RS256 JWT, Refresh Tokens & OAuth 2.0 PKCE

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Security Engineering, JWT Signatures & OAuth 2.0 Authorization

---

## 1. Authentication Architectural Paradigms

```text
┌─────────────────────────────────────────────────────────────┐
│                 Session vs Stateless JWT Tokens             │
├────────────────────┬────────────────────────────────────────┤
│ **Stateful**       │ **Redis-Backed Session IDs**           │
│ **Sessions**       │ - Server stores session object in RAM. │
│                    │ - Immediate instant revocation.        │
│                    │ - Requires central database / cache.   │
├────────────────────┼────────────────────────────────────────┤
│ **Stateless**      │ **Asymmetrically Signed (RS256/EdDSA)**│
│ **JWT Tokens**     │ - Self-contained payload.              │
│                    │ - Any microservice can verify token    │
│                    │   using the Public Key (Zero DB hit!)  │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Asymmetric RS256 JWT Authentication with `jsonwebtoken`

Never sign enterprise JWTs using symmetric HS256 shared secrets (because every microservice verifying the token would need access to the private signing secret!).

Always use **RS256 (RSA Signature with SHA-256)**:

- **Private Key**: Kept exclusively on the Auth Service to sign tokens.
- **Public Key**: Distributed to all microservices / API gateways to verify tokens locally in **< 1ms with zero database queries**.

```bash
npm install jsonwebtoken
```

```javascript
// src/auth/jwt_service.js
import jwt from 'jsonwebtoken';
import fs from 'node:fs';

const PRIVATE_KEY = fs.readFileSync('certs/jwt_rsa_private.pem', 'utf8');
const PUBLIC_KEY = fs.readFileSync('certs/jwt_rsa_public.pem', 'utf8');

export class JwtTokenService {
  /**

   * Signs a short-lived Access Token (15 Minutes):
   */
  static generateAccessToken(user) {
    return jwt.sign(
      {
        sub: user.id,
        email: user.email,
        role: user.role,
        permissions: user.permissions || [],
      },
      PRIVATE_KEY,
      {
        algorithm: 'RS256',
        expiresIn: '15m',
        issuer: 'auth.enterprise.acme.com',
        audience: 'api.enterprise.acme.com',
      }
    );
  }

  /**

   * Signs a long-lived Refresh Token (7 Days):
   */
  static generateRefreshToken(userId, tokenFamilyId) {
    return jwt.sign(
      { sub: userId, familyId: tokenFamilyId },
      PRIVATE_KEY,
      {
        algorithm: 'RS256',
        expiresIn: '7d',
        issuer: 'auth.enterprise.acme.com',
      }
    );
  }

  /**

   * Verifies an Access Token using the Public Key:
   */
  static verifyAccessToken(token) {
    try {
      return jwt.verify(token, PUBLIC_KEY, {
        algorithms: ['RS256'],
        issuer: 'auth.enterprise.acme.com',
        audience: 'api.enterprise.acme.com',
      });
    } catch (err) {
      throw new Error(`Token verification failed: ${err.message}`);
    }
  }
}
```

---

## 3. Refresh Token Rotation & Breach Containment

To prevent stolen refresh tokens from providing permanent attacker access, implement **Refresh Token Rotation with Automatic Token Reuse Detection**:

```text
Token Rotation Flow:
1. Client sends Refresh Token A.
2. Server validates Token A, invalidates Token A, and issues Refresh Token B.
3. If an attacker attempts to reuse already-invalidated Token A:
   ──► REUSE DETECTED!
   ──► Server immediately revokes the ENTIRE Token Family (All active sessions terminated)!
```

```javascript
// src/auth/token_rotator.js
import { redis } from '../cache/redis_client.js';
import { JwtTokenService } from './jwt_service.js';

export async function rotateRefreshToken(oldRefreshToken) {
  const decoded = JwtTokenService.verifyAccessToken(oldRefreshToken);
  const { sub: userId, familyId } = decoded;

  const familyKey = `token_family:${userId}:${familyId}`;

  // 1. Get current active token in family from Redis:
  const activeToken = await redis.get(familyKey);

  // 2. TOKEN REUSE BREACH DETECTION:
  if (activeToken && activeToken !== oldRefreshToken) {
    console.error(`🚨 SECURITY ALERT: Refresh token reuse detected for User ${userId}!`);
    // Revoke all tokens for this user immediately:
    await redis.del(familyKey);
    throw new Error('Security Breach: Token reuse detected. Please log in again.');
  }

  // 3. Issue fresh token pair:
  const newAccessToken = JwtTokenService.generateAccessToken({ id: userId });
  const newRefreshToken = JwtTokenService.generateRefreshToken(userId, familyId);

  // 4. Update active token in Redis with 7-day TTL:
  await redis.set(familyKey, newRefreshToken, 'EX', 7 * 24 * 3600);

  return {
    accessToken: newAccessToken,
    refreshToken: newRefreshToken,
  };
}
```

---

## 4. Role-Based Access Control (RBAC) Middleware

```javascript
// src/middleware/rbac_guard.js
import { JwtTokenService } from '../auth/jwt_service.js';

export function requireRole(...allowedRoles) {
  return (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: Missing Bearer Token' });
    }

    const token = authHeader.split(' ')[1];

    try {
      // Verify token with public key:
      const payload = JwtTokenService.verifyAccessToken(token);
      req.user = payload;

      // Check RBAC role permission:
      if (!allowedRoles.includes(payload.role)) {
        return res.status(403).json({
          error: 'Forbidden: Insufficient permissions for this resource',
          requiredRoles: allowedRoles,
        });
      }

      next();
    } catch (err) {
      return res.status(401).json({ error: 'Invalid or expired token', message: err.message });
    }
  };
}
```

---

## 5. OAuth 2.0 Authorization Code Grant with PKCE

For Single Page Apps (React/Vue) and Mobile Apps (Flutter/iOS), always enforce **Proof Key for Code Exchange (PKCE)** to prevent authorization code interception:

```javascript
import crypto from 'node:crypto';

// 1. Client generates PKCE Code Verifier & Code Challenge:
export function generatePkcePair() {
  const codeVerifier = crypto.randomBytes(32).toString('base64url');

  const codeChallenge = crypto
    .createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');

  return { codeVerifier, codeChallenge };
}

// 2. Server verifies Code Verifier matches original Code Challenge:
export function verifyPkce(codeVerifier, expectedCodeChallenge) {
  const computedChallenge = crypto
    .createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');

  return crypto.timingSafeEqual(
    Buffer.from(computedChallenge),
    Buffer.from(expectedCodeChallenge)
  );
}
```

---

## Troubleshooting & Best Practices

1. **Never Store Access Tokens in `localStorage`**
   Storing JWTs in browser `localStorage` leaves them completely vulnerable to Cross-Site Scripting (XSS) data exfiltration. Store Refresh Tokens in **`HttpOnly; Secure; SameSite=Strict`** cookies.

2. **Always Validate `iss` (Issuer) and `aud` (Audience)**
   When verifying tokens with `jwt.verify()`, always explicitly enforce `issuer` and `audience` options to prevent tokens signed for a different internal service from being replayed.
