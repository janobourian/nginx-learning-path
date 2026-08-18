# Module 05: The Fetch API, `AbortController` & Web Streams

**Track:** Modern JavaScript — Frontend Architecture & Web APIs  
**Category:** Networking Standards, HTTP Streaming & Cancellation Architecture

---

## 1. The Modern Fetch Architecture (`Request`, `Response`, `Headers`)

The standard **Fetch API** replaced legacy `XMLHttpRequest` with a clean, Promise-based model built on three foundational interfaces:

```
┌─────────────────────────────────────────────────────────────┐
│                     The Fetch API Trilogy                   │
├────────────────────┬────────────────────────────────────────┤
│ **`Request`**      │ Encapsulates URL, method, headers,     │
│                    │ body, and caching policies.            │
├────────────────────┼────────────────────────────────────────┤
│ **`Response`**     │ Represents the HTTP response status,   │
│                    │ headers, and streaming body stream.    │
├────────────────────┼────────────────────────────────────────┤
│ **`Headers`**      │ Case-insensitive map of HTTP headers   │
│                    │ (`headers.get('content-type')`).       │
└────────────────────┴────────────────────────────────────────┘
```

---

## 2. Request Timeouts & Cancellation with `AbortController`

A common issue with `fetch` is that Promises cannot be canceled natively. If a user navigates away or an API hangs, outstanding network sockets remain open.

Use **`AbortController`** and **`AbortSignal.timeout()`**:

```javascript
// 1. Declarative 5-Second Timeout (Native in modern browsers):
async function fetchWithTimeout(url) {
  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(5000), // Auto-aborts after 5,000ms!
    });
    return await response.json();
  } catch (error) {
    if (error.name === 'TimeoutError') {
      console.error('Request timed out after 5 seconds.');
    }
    throw error;
  }
}

// 2. Manual User-Driven Cancellation (e.g. Cancel button):
const controller = new AbortController();

fetch('/api/heavy-export', { signal: controller.signal })
  .then((res) => res.json())
  .catch((err) => {
    if (err.name === 'AbortError') {
      console.log('User cancelled request safely.');
    }
  });

// Cancel whenever needed:
document.querySelector('#cancel-btn').addEventListener('click', () => {
  controller.abort('User clicked cancel button');
});
```

---

## 3. Real-Time LLM Token Streaming (`response.body.getReader()`)

Consuming streaming AI responses (ChatGPT/Claude token-by-token generation) using **Web Streams** and **`TextDecoderStream`**:

```javascript
// src/network/llm_stream.js
export async function streamAiResponse(prompt, onTokenReceived) {
  const response = await fetch('/api/v1/generate-ai', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt }),
  });

  if (!response.ok) {
    throw new Error(`AI Gateway error: ${response.status}`);
  }

  // 1. Get raw binary ReadableStream reader:
  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf8');

  let fullText = '';

  while (true) {
    // 2. Read next binary chunk as it arrives over the network:
    const { done, value } = await reader.read();

    if (done) {
      console.log('AI Generation Stream completed.');
      break;
    }

    // 3. Decode binary chunk to text token:
    const chunkText = decoder.decode(value, { stream: true });
    fullText += chunkText;

    // 4. Update UI in real-time without waiting for full response!
    onTokenReceived(chunkText, fullText);
  }

  return fullText;
}

// UI Consumption:
const outputElement = document.querySelector('#ai-output');
streamAiResponse('Explain quantum computing', (newToken) => {
  outputElement.textContent += newToken;
});
```

---

## 4. Building an Enterprise Resilient HTTP Client (Vanilla JS)

Let's build a production-grade API client featuring **Interceptors**, **Auth Token Injection**, and **Exponential Backoff Retries**:

```javascript
// src/network/api_client.js
export class ResilientHttpClient {
  constructor(baseUrl, getAuthToken) {
    this.baseUrl = baseUrl;
    this.getAuthToken = getAuthToken;
  }

  async request(endpoint, options = {}, retries = 3) {
    const url = `${this.baseUrl}${endpoint}`;
    const token = await this.getAuthToken();

    // 1. Request Interceptor (Header injection):
    const headers = new Headers(options.headers);
    headers.set('Accept', 'application/json');
    if (!headers.has('Content-Type') && options.body && typeof options.body === 'string') {
      headers.set('Content-Type', 'application/json');
    }
    if (token) {
      headers.set('Authorization', `Bearer ${token}`);
    }

    const config = { ...options, headers };

    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        const response = await fetch(url, config);

        // Handle HTTP Error Statuses:
        if (!response.ok) {
          if (response.status >= 500 && attempt < retries) {
            // Server Error (5xx) -> Retry with exponential backoff!
            const delay = Math.pow(2, attempt) * 500;
            console.warn(`Attempt ${attempt} failed with ${response.status}. Retrying in ${delay}ms...`);
            await new Promise((r) => setTimeout(r, delay));
            continue;
          }

          const errorBody = await response.json().catch(() => ({}));
          throw new Error(errorBody.message || `HTTP ${response.status}: ${response.statusText}`);
        }

        return await response.json();
      } catch (err) {
        if (attempt === retries || err.name === 'AbortError') {
          throw err;
        }
        const delay = Math.pow(2, attempt) * 500;
        await new Promise((r) => setTimeout(r, delay));
      }
    }
  }

  get(endpoint, options) {
    return this.request(endpoint, { ...options, method: 'GET' });
  }

  post(endpoint, body, options) {
    return this.request(endpoint, {
      ...options,
      method: 'POST',
      body: JSON.stringify(body),
    });
  }
}
```

---

## Troubleshooting & Best Practices

1. **`fetch()` Does NOT Reject on 404 or 500 Errors**
   A common beginner bug: `fetch()` only rejects its Promise on **network connection failures** (DNS failure, offline, CORS block). It resolves successfully on HTTP 404 and 500. Always check **`if (!response.ok) { throw Error(...) }`**.

2. **Always Use `AbortSignal.any()` to Combine Cancellation Signals**
   In modern browsers, combine a user cancellation signal with a timeout signal using `signal: AbortSignal.any([userSignal, AbortSignal.timeout(10000)])`.
