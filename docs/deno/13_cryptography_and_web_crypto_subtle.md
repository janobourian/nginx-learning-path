# Module 13: Cryptography & Web Crypto SubtleCrypto

**Track:** Deno Secure Engine & Edge Runtime
**Category:** Security & Cryptographic Operations

---

## Cryptography in Deno

Deno exposes the browser's **Web Crypto API** (`crypto` and `crypto.subtle`) as a first-class global. This is the same API available in modern browsers and Cloudflare Workers — code that uses Web Crypto runs unchanged across all these runtimes.

The key advantage over Node.js's `crypto` module is standards compliance: Web Crypto is a W3C specification, so behavior is consistent across implementations. It also handles key material securely — CryptoKey objects store key bytes in the runtime's memory in a way that cannot be accidentally serialized or logged.

---

## Random Values

```typescript
// Cryptographically secure random bytes (backed by OS CSPRNG)
const randomBytes = new Uint8Array(32);
crypto.getRandomValues(randomBytes);

// Convert to hex string
const hexToken = Array.from(randomBytes)
  .map((b) => b.toString(16).padStart(2, "0"))
  .join("");
console.log(hexToken);  // 64-character hex string

// Generate a UUID v4 (uses CSPRNG internally)
const id = crypto.randomUUID();
console.log(id);  // "a4e1f9c2-3b5d-4e67-8f01-9a2b3c4d5e6f"

// Generate an API key (base64url encoded)
function generateApiKey(length = 32): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

const apiKey = generateApiKey(32);  // 43-character URL-safe string
```

---

## Hashing with `crypto.subtle.digest`

```typescript
async function sha256(input: string | Uint8Array): Promise<Uint8Array> {
  const data = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return new Uint8Array(hashBuffer);
}

async function sha256Hex(input: string): Promise<string> {
  const hash = await sha256(input);
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha512Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-512", data);
  const hash = new Uint8Array(hashBuffer);
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Supported algorithms: SHA-1, SHA-256, SHA-384, SHA-512
// SHA-1 is deprecated for security use — only use for legacy compatibility

console.log(await sha256Hex("Hello, World!"));
// "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986d"
```

---

## HMAC — Message Authentication Codes

HMAC proves that a message was signed by someone who knows the secret key and has not been tampered with:

```typescript
// Generate an HMAC-SHA256 key
async function generateHMACKey(): Promise<CryptoKey> {
  return await crypto.subtle.generateKey(
    { name: "HMAC", hash: "SHA-256" },
    true,      // extractable — allows exporting the key
    ["sign", "verify"],
  );
}

// Sign a message
async function signHMAC(key: CryptoKey, message: string): Promise<string> {
  const data = new TextEncoder().encode(message);
  const signature = await crypto.subtle.sign("HMAC", key, data);
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

// Verify a signature
async function verifyHMAC(key: CryptoKey, message: string, signature: string): Promise<boolean> {
  const data = new TextEncoder().encode(message);
  const sigBytes = Uint8Array.from(atob(signature), (c) => c.charCodeAt(0));
  return await crypto.subtle.verify("HMAC", key, sigBytes, data);
}

// Export a CryptoKey to raw bytes for storage
async function exportKey(key: CryptoKey): Promise<string> {
  const exported = await crypto.subtle.exportKey("raw", key);
  return btoa(String.fromCharCode(...new Uint8Array(exported)));
}

// Import a key from stored bytes
async function importHMACKey(base64Key: string): Promise<CryptoKey> {
  const keyBytes = Uint8Array.from(atob(base64Key), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,     // Not extractable once imported from storage
    ["sign", "verify"],
  );
}

// Full example: signed webhook payloads (like GitHub webhook signatures)
async function createWebhookSignature(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const hex = Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `sha256=${hex}`;
}

async function verifyWebhookSignature(secret: string, payload: string, header: string): Promise<boolean> {
  const expected = await createWebhookSignature(secret, payload);
  // Timing-safe comparison prevents timing attacks
  if (expected.length !== header.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ header.charCodeAt(i);
  }
  return mismatch === 0;
}
```

---

## AES-GCM Symmetric Encryption

AES-256-GCM provides authenticated encryption — the cipher both encrypts the data and includes an authentication tag that detects tampering:

```typescript
// Generate a 256-bit AES-GCM key
async function generateAESKey(): Promise<CryptoKey> {
  return await crypto.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    true,      // extractable
    ["encrypt", "decrypt"],
  );
}

// Encrypt plaintext → returns { ciphertext, iv }
async function encryptAES(key: CryptoKey, plaintext: string): Promise<{ ciphertext: string; iv: string }> {
  const data = new TextEncoder().encode(plaintext);
  const iv = new Uint8Array(12);  // 96-bit IV for AES-GCM — never reuse!
  crypto.getRandomValues(iv);

  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    data,
  );

  return {
    ciphertext: btoa(String.fromCharCode(...new Uint8Array(encrypted))),
    iv: btoa(String.fromCharCode(...iv)),
  };
}

// Decrypt { ciphertext, iv } → plaintext
async function decryptAES(key: CryptoKey, ciphertext: string, iv: string): Promise<string> {
  const cipherBytes = Uint8Array.from(atob(ciphertext), (c) => c.charCodeAt(0));
  const ivBytes = Uint8Array.from(atob(iv), (c) => c.charCodeAt(0));

  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: ivBytes },
    key,
    cipherBytes,
  );

  return new TextDecoder().decode(decrypted);
}

// Usage
const key = await generateAESKey();
const { ciphertext, iv } = await encryptAES(key, "Secret message: API key is abc123");
console.log("Encrypted:", ciphertext);

const decrypted = await decryptAES(key, ciphertext, iv);
console.log("Decrypted:", decrypted);  // "Secret message: API key is abc123"
```

---

## RSA Asymmetric Encryption and Signing

```typescript
// Generate RSA-OAEP key pair for encryption/decryption
async function generateRSAEncryptionKeyPair(): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey(
    {
      name: "RSA-OAEP",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),  // 65537
      hash: "SHA-256",
    },
    true,
    ["encrypt", "decrypt"],
  );
}

// Generate RSA-PSS key pair for digital signatures
async function generateRSASigningKeyPair(): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey(
    {
      name: "RSA-PSS",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
}

// Sign with private key
async function rsaSign(privateKey: CryptoKey, data: string): Promise<Uint8Array> {
  const encoded = new TextEncoder().encode(data);
  const signature = await crypto.subtle.sign(
    { name: "RSA-PSS", saltLength: 32 },
    privateKey,
    encoded,
  );
  return new Uint8Array(signature);
}

// Verify with public key
async function rsaVerify(publicKey: CryptoKey, data: string, signature: Uint8Array): Promise<boolean> {
  const encoded = new TextEncoder().encode(data);
  return await crypto.subtle.verify(
    { name: "RSA-PSS", saltLength: 32 },
    publicKey,
    signature,
    encoded,
  );
}

// Export public key to PEM for sharing
async function exportPublicKeyToPEM(key: CryptoKey): Promise<string> {
  const exported = await crypto.subtle.exportKey("spki", key);
  const base64 = btoa(String.fromCharCode(...new Uint8Array(exported)));
  const pem = base64.match(/.{1,64}/g)!.join("\n");
  return `-----BEGIN PUBLIC KEY-----\n${pem}\n-----END PUBLIC KEY-----`;
}
```

---

## ECDH Key Exchange

Elliptic Curve Diffie-Hellman allows two parties to establish a shared secret over an insecure channel:

```typescript
// Generate ECDH key pair
async function generateECDHKeyPair(): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveKey", "deriveBits"],
  );
}

// Derive a shared AES key from two ECDH public keys
async function deriveSharedKey(privateKey: CryptoKey, otherPublicKey: CryptoKey): Promise<CryptoKey> {
  return await crypto.subtle.deriveKey(
    { name: "ECDH", public: otherPublicKey },
    privateKey,
    { name: "AES-GCM", length: 256 },
    false,     // Not extractable
    ["encrypt", "decrypt"],
  );
}

// Alice and Bob establish a shared key without sending it over the wire
const aliceKeys = await generateECDHKeyPair();
const bobKeys = await generateECDHKeyPair();

// Alice derives shared key using Bob's public key
const aliceSharedKey = await deriveSharedKey(aliceKeys.privateKey, bobKeys.publicKey);

// Bob derives the same shared key using Alice's public key
const bobSharedKey = await deriveSharedKey(bobKeys.privateKey, aliceKeys.publicKey);

// Both keys are equivalent — they can now encrypt to each other
const { ciphertext, iv } = await encryptAES(aliceSharedKey, "Hello from Alice!");
const message = await decryptAES(bobSharedKey, ciphertext, iv);
console.log(message);  // "Hello from Alice!"
```

---

## Password Hashing with PBKDF2

For storing user passwords, use PBKDF2 (Password-Based Key Derivation Function 2) which is intentionally slow to resist brute-force attacks:

```typescript
async function hashPassword(password: string): Promise<{ hash: string; salt: string }> {
  const salt = new Uint8Array(16);
  crypto.getRandomValues(salt);

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt,
      iterations: 600_000,  // NIST recommended minimum in 2024
    },
    keyMaterial,
    256,  // 32 bytes = 256 bits
  );

  const hashBytes = new Uint8Array(derivedBits);
  return {
    hash: btoa(String.fromCharCode(...hashBytes)),
    salt: btoa(String.fromCharCode(...salt)),
  };
}

async function verifyPassword(password: string, storedHash: string, storedSalt: string): Promise<boolean> {
  const salt = Uint8Array.from(atob(storedSalt), (c) => c.charCodeAt(0));

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );

  const derivedBits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: 600_000 },
    keyMaterial,
    256,
  );

  const hashBytes = new Uint8Array(derivedBits);
  const computedHash = btoa(String.fromCharCode(...hashBytes));

  // Constant-time comparison
  return computedHash === storedHash;
}
```

---

## Troubleshooting

### `DOMException: algorithm: Unrecognized name`

Algorithm names must match exactly (case matters for some implementations). Use: `"SHA-256"`, `"AES-GCM"`, `"HMAC"`, `"RSA-PSS"`, `"RSA-OAEP"`, `"ECDH"`, `"ECDSA"`, `"PBKDF2"`.

### `DOMException: Decryption failed`

AES-GCM decryption fails if: the IV doesn't match the one used for encryption, the ciphertext has been tampered with (authentication tag mismatch), or the key is wrong. AES-GCM's authentication tag catches any modification.

### PBKDF2 is very slow — blocking the event loop

`crypto.subtle.deriveBits` with PBKDF2 and high iteration counts runs synchronously in the V8 thread, blocking the event loop for 100-500ms. This is expected (the slowness is the security). For a web server, run password hashing in a worker or accept the latency on auth endpoints only.
