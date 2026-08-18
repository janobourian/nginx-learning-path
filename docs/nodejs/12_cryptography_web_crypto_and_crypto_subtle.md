# Module 12: Enterprise Cryptography — Web Crypto (`crypto.subtle`) & OpenSSL

**Track:** Node.js — Enterprise Architecture & Libuv Internals  
**Category:** Cryptography, AES-256-GCM, Digital Signatures & Web Crypto

---

## 1. Node.js Dual Cryptography APIs

Node.js offers two distinct cryptography APIs:

```
┌─────────────────────────────────────────────────────────────┐
│                 Node.js Cryptography APIs                   │
├────────────────────┬────────────────────────────────────────┤
│ **1. Web Crypto**  │ **`crypto.subtle` (W3C Web Standard)** │
│    **API**         │ - Works identically in Node.js, Deno,  │
│                    │   Cloudflare Workers, and Browsers.    │
│                    │ - Promise-based async API.             │
├────────────────────┼────────────────────────────────────────┤
│ **2. Node.js Core**│ **`import crypto from 'node:crypto'`** │
│    **Crypto**      │ - Low-level OpenSSL bindings.          │
│                    │ - Streaming ciphers & hashes.          │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Authenticated Symmetric Encryption with AES-256-GCM

Never use unauthenticated modes like AES-CBC or AES-ECB. Always use **AES-256-GCM (Galois/Counter Mode)**, which provides **Authenticated Encryption with Associated Data (AEAD)**:

```javascript
// src/security/aes_gcm.js
import crypto from 'node:crypto';

export class AesGcmVault {
  static ALGORITHM = 'aes-256-gcm';
  static IV_LENGTH = 12; // 96-bit Initialization Vector (Standard for GCM)
  static AUTH_TAG_LENGTH = 16; // 128-bit Authentication Tag

  /**
   * Encrypts plaintext into a secure envelope format:
   * [IV (12B)] + [Auth Tag (16B)] + [Ciphertext (NB)]
   */
  static encrypt(plaintext, keyBuffer) {
    if (keyBuffer.length !== 32) {
      throw new Error('Key must be exactly 32 bytes (256 bits).');
    }

    // 1. Generate unique random IV for EVERY encryption:
    const iv = crypto.randomBytes(this.IV_LENGTH);

    // 2. Create Cipher:
    const cipher = crypto.createCipheriv(this.ALGORITHM, keyBuffer, iv, {
      authTagLength: this.AUTH_TAG_LENGTH,
    });

    const encrypted = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final(),
    ]);

    // 3. Extract GCM Authentication Tag:
    const authTag = cipher.getAuthTag();

    // 4. Return combined buffer (Base64 URL Safe):
    return Buffer.concat([iv, authTag, encrypted]).toString('base64url');
  }

  /**
   * Decrypts and verifies the ciphertext authenticity:
   */
  static decrypt(payloadBase64Url, keyBuffer) {
    const payload = Buffer.from(payloadBase64Url, 'base64url');

    if (payload.length < this.IV_LENGTH + this.AUTH_TAG_LENGTH) {
      throw new Error('Invalid ciphertext payload size.');
    }

    // 1. Extract components:
    const iv = payload.subarray(0, this.IV_LENGTH);
    const authTag = payload.subarray(this.IV_LENGTH, this.IV_LENGTH + this.AUTH_TAG_LENGTH);
    const ciphertext = payload.subarray(this.IV_LENGTH + this.AUTH_TAG_LENGTH);

    // 2. Create Decipher:
    const decipher = crypto.createDecipheriv(this.ALGORITHM, keyBuffer, iv, {
      authTagLength: this.AUTH_TAG_LENGTH,
    });

    // 3. Set Expected Auth Tag (Fails if data was tampered with!):
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);

    return decrypted.toString('utf8');
  }
}
```

---

## 3. Modern W3C Web Crypto Standard (`crypto.subtle`)

Use `crypto.subtle` for cross-runtime code compatible with Cloudflare Workers, Next.js Edge Middleware, and Browsers:

```javascript
// src/security/web_crypto_ecdsa.js

export async function generateEcdsaKeyPair() {
  // Generate ECDSA P-256 Key Pair:
  return await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true, // Extractable
    ['sign', 'verify']
  );
}

export async function signData(privateKey, dataString) {
  const encoder = new TextEncoder();
  const data = encoder.encode(dataString);

  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: { name: 'SHA-256' } },
    privateKey,
    data
  );

  return Buffer.from(signature).toString('base64url');
}

export async function verifySignature(publicKey, signatureBase64Url, dataString) {
  const encoder = new TextEncoder();
  const data = encoder.encode(dataString);
  const signature = Buffer.from(signatureBase64Url, 'base64url');

  return await crypto.subtle.verify(
    { name: 'ECDSA', hash: { name: 'SHA-256' } },
    publicKey,
    signature,
    data
  );
}
```

---

## 4. Preventing Timing Attacks with `crypto.timingSafeEqual`

When verifying HMAC signatures, API keys, or webhooks, using standard string comparison (`secretA === secretB`) is vulnerable to **Side-Channel Timing Attacks** (attackers measure microscopic nanosecond differences in string comparison execution times to guess characters one-by-one).

Always use **`crypto.timingSafeEqual`**:

```javascript
import crypto from 'node:crypto';

export function verifyWebhookSignature(payload, signatureHeader, secretKey) {
  // 1. Compute expected HMAC:
  const expectedHmac = crypto
    .createHmac('sha256', secretKey)
    .update(payload)
    .digest();

  const providedHmac = Buffer.from(signatureHeader, 'hex');

  if (expectedHmac.length !== providedHmac.length) {
    return false;
  }

  // 2. Constant-Time Comparison (Zero timing side-channel leakage!):
  return crypto.timingSafeEqual(expectedHmac, providedHmac);
}
```

---

## 5. Password Hashing with `crypto.scrypt` & Argon2

Never use fast cryptographic hash functions like SHA-256 or MD5 for passwords; GPUs can compute billions of SHA-256 hashes per second.

Use **`crypto.scrypt`** (memory-hard, resistant to GPU/ASIC cracking):

```javascript
import crypto from 'node:crypto';

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, 64, { N: 16384, r: 8, p: 1 }, (err, derivedKey) => {
      if (err) return reject(err);
      resolve(`${salt}:${derivedKey.toString('hex')}`);
    });
  });
}

export async function verifyPassword(password, storedHash) {
  const [salt, key] = storedHash.split(':');
  const keyBuffer = Buffer.from(key, 'hex');

  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, 64, { N: 16384, r: 8, p: 1 }, (err, derivedKey) => {
      if (err) return reject(err);
      resolve(crypto.timingSafeEqual(keyBuffer, derivedKey));
    });
  });
}
```

---

## Troubleshooting & Best Practices

1. **Never Reuse an Initialization Vector (IV)**
   In AES-GCM, encrypting two different messages with the same key and same IV leaks the XOR difference of the plaintexts and destroys the cryptographic security of the GCM authentication key. Always generate a fresh `crypto.randomBytes(12)` for every encryption call.

2. **Always Use `timingSafeEqual` for Tokens**
   Always verify authentication tokens and webhook signatures with `crypto.timingSafeEqual(bufA, bufB)` rather than `===`.
