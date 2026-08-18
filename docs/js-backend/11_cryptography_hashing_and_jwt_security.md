# Module 11: Backend Cryptography — AES-256-GCM, Ed25519 Signatures & JWT Hardening

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Cryptography, Identity Engineering & JWT Token Security

---

## 1. Cryptographic Primitive Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                 Enterprise Cryptography Primitives          │
├────────────────────┬────────────────────────────────────────┤
│ **1. Symmetric**   │ **AES-256-GCM** or **ChaCha20-Poly1305**│
│    **Encryption**  │ - Authenticated Encryption (AEAD).     │
│                    │ - Prevents data tampering & bit-flips. │
├────────────────────┼────────────────────────────────────────┤
│ **2. Digital**     │ **Ed25519 (EdDSA)** or **ECDSA (P-256)**│
│    **Signatures**  │ - Ultra-fast asymmetric signatures.    │
│                    │ - 64-byte compact signature length.    │
├────────────────────┼────────────────────────────────────────┤
│ **3. Password**    │ **Argon2id** (Winner of Password Hashing│
│    **Hashing**     │ Competition) or **Scrypt**.            │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Ultra-Fast Digital Signatures with Ed25519 (`node:crypto`)

**Ed25519** is modern, immune to side-channel timing attacks, and significantly faster than legacy RSA-4096:

```javascript
// src/security/ed25519_signatures.js
import crypto from 'node:crypto';

export class Ed25519Signer {
  // 1. Generate Ed25519 Key Pair:
  static generateKeyPair() {
    return crypto.generateKeyPairSync('ed25519', {
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
  }

  // 2. Sign Data Payload:
  static sign(dataString, privateKeyPem) {
    const dataBuffer = Buffer.from(dataString, 'utf8');
    const signature = crypto.sign(null, dataBuffer, privateKeyPem);
    return signature.toString('base64url');
  }

  // 3. Verify Signature:
  static verify(dataString, signatureBase64Url, publicKeyPem) {
    const dataBuffer = Buffer.from(dataString, 'utf8');
    const signature = Buffer.from(signatureBase64Url, 'base64url');
    return crypto.verify(null, dataBuffer, publicKeyPem, signature);
  }
}
```

---

## 3. Hardened JWT Implementation (Preventing Algorithm Confusion Attacks)

Common security flaws in JWT libraries:
1. **`alg: none` Vulnerability**: Attackers modify header to `"alg": "none"` to bypass verification.
2. **Algorithm Confusion**: Attacker verifies an RS256 token using the public key as an HS256 HMAC secret!

### Secure JWT Verification Engine:

```javascript
// src/security/secure_jwt.js
import crypto from 'node:crypto';

export class SecureJwtEngine {
  constructor(publicKeyPem, issuer, audience) {
    this.publicKeyPem = publicKeyPem;
    this.issuer = issuer;
    this.audience = audience;
  }

  verify(tokenString) {
    const parts = tokenString.split('.');
    if (parts.length !== 3) throw new Error('Malformed JWT token structure');

    const [headerB64, payloadB64, signatureB64] = parts;

    // 1. Validate Header:
    const header = JSON.parse(Buffer.from(headerB64, 'base64url').toString('utf8'));

    // STRICT CHECK: Reject any algorithm other than Ed25519!
    if (header.alg !== 'EdDSA') {
      throw new Error(`Forbidden JWT algorithm: ${header.alg}. Only EdDSA is permitted.`);
    }

    // 2. Cryptographic Signature Verification:
    const signedData = `${headerB64}.${payloadB64}`;
    const isValid = crypto.verify(
      null,
      Buffer.from(signedData, 'utf8'),
      this.publicKeyPem,
      Buffer.from(signatureB64, 'base64url')
    );

    if (!isValid) throw new Error('Invalid JWT cryptographic signature');

    // 3. Validate Claims & Expiration:
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    const now = Math.floor(Date.now() / 1000);

    if (payload.exp && payload.exp < now) throw new Error('JWT token has expired');
    if (this.issuer && payload.iss !== this.issuer) throw new Error('Invalid token issuer');
    if (this.audience && payload.aud !== this.audience) throw new Error('Invalid token audience');

    return payload;
  }
}
```

---

## 4. Zeroing Sensitive Cryptographic Buffers in Memory

In high-security banking/cryptographic applications, leaving passwords or private keys in memory allows core dumps to expose secrets.

**Explicitly overwrite buffers with zeros immediately after use**:

```javascript
export function executeSecureCryptoOperation(sensitivePassword) {
  const secretBuffer = Buffer.from(sensitivePassword, 'utf8');

  try {
    // Perform encryption / hashing:
    // ...
  } finally {
    // CRITICAL: Overwrite raw RAM bytes with 0x00:
    secretBuffer.fill(0);
  }
}
```

---

## Troubleshooting & Best Practices

1. **Always Use Authenticated Symmetric Encryption (AEAD)**
   Never use `aes-256-cbc` without an HMAC. Attackers can perform Bit-Flipping and Padding Oracle attacks. Always use **`aes-256-gcm`** with authentication tags.

2. **Enforce Strict `algorithms` Whitelist in JWT Libraries**
   When using third-party libraries (e.g. `jsonwebtoken`), always pass `algorithms: ['RS256']` explicitly in `jwt.verify(token, key, { algorithms: ['RS256'] })` to eliminate algorithm confusion vulnerabilities.
