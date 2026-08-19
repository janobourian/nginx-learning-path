# Module 06: HTTP, HTTPS & HTTP/2 Multiplexed Servers

**Track:** Node.js — Enterprise Architecture & Libuv Internals
**Category:** Networking Architecture, HTTP Protocols & TLS Encryption

---

## 1. Low-Level HTTP Server Architecture (`node:http`)

Every web framework in Node.js (Express, Fastify, NestJS) is built on top of the built-in **`node:http`** module.

```javascript
import http from 'node:http';

const server = http.createServer(async (req, res) => {
  const { method, url, headers } = req;

  // 1. Parsing Streaming Request Body:
  if (method === 'POST' && url === '/api/data') {
    const chunks = [];

    for await (const chunk of req) {
      chunks.push(chunk);
    }

    const body = Buffer.concat(chunks).toString('utf8');
    const json = JSON.parse(body);

    // 2. Sending Response:
    res.writeHead(201, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ received: json }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Route Not Found');
});

server.listen(3000, () => {
  console.log('HTTP/1.1 Server listening on port 3000');
});
```

---

## 2. HTTPS & TLS Encryption (`node:https`)

Production HTTPS servers terminate TLS using OpenSSL certificates:

```javascript
import https from 'node:https';
import fs from 'node:fs';

const tlsOptions = {
  // SSL Certificate & Private Key:
  key: fs.readFileSync('certs/privkey.pem'),
  cert: fs.readFileSync('certs/fullchain.pem'),

  // Modern Hardened TLS Configuration:
  minVersion: 'TLSv1.2',
  ciphers: [
    'ECDHE-ECDSA-AES128-GCM-SHA256',
    'ECDHE-RSA-AES128-GCM-SHA256',
    'ECDHE-ECDSA-AES256-GCM-SHA384',
    'ECDHE-RSA-AES256-GCM-SHA384',
  ].join(':'),
  honorCipherOrder: true,
};

const httpsServer = https.createServer(tlsOptions, (req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Secure HTTPS Connection Established.');
});

httpsServer.listen(443, () => {
  console.log('HTTPS Server listening on port 443');
});
```

---

## 3. High-Performance HTTP/2 Architecture (`node:http2`)

While HTTP/1.1 requires opening separate TCP connections for parallel requests (or suffers from Head-of-Line blocking), **HTTP/2 multiplexes hundreds of concurrent requests and responses over a single TCP connection**:

```text
HTTP/1.1 (Multiple TCP Sockets):
Connection 1: ──► [Request 1] ──► [Response 1]
Connection 2: ──► [Request 2] ──► [Response 2]

HTTP/2 Multiplexing (Single TCP Socket):
Single Socket: ──► [Stream 1: Data] [Stream 2: Data] [Stream 1: Headers] ──►
```

### Implementing an HTTP/2 Server in Node.js

```javascript
// src/servers/http2_server.js
import http2 from 'node:http2';
import fs from 'node:fs';

const server = http2.createSecureServer({
  key: fs.readFileSync('certs/privkey.pem'),
  cert: fs.readFileSync('certs/fullchain.pem'),
  allowHTTP1: true, // Fallback to HTTP/1.1 for legacy clients via ALPN negotiation!
});

server.on('stream', (stream, headers) => {
  const path = headers[':path'];
  const method = headers[':method'];

  console.log(`[HTTP/2 Stream #${stream.id}]: ${method} ${path}`);

  if (path === '/' && method === 'GET') {
    // 1. HTTP/2 Server Push (Push CSS assets before client requests them!):
    stream.pushStream({ ':path': '/style.css' }, (err, pushStream) => {
      if (!err) {
        pushStream.respond({
          ':status': 200,
          'content-type': 'text/css',
        });
        pushStream.end('body { background: #0f172a; color: #f8fafc; }');
      }
    });

    // 2. Respond to main HTML stream:
    stream.respond({
      ':status': 200,
      'content-type': 'text/html; charset=utf-8',
    });
    stream.end(`
      <!DOCTYPE html>
      <html>
        <head><link rel="stylesheet" href="/style.css"></head>
        <body>
          <h1>HTTP/2 Multiplexed Enterprise Stream</h1>
          <p>Stream ID: ${stream.id}</p>
        </body>
      </html>
    `);
    return;
  }

  stream.respond({ ':status': 404 });
  stream.end('Not Found');
});

server.listen(8443, () => {
  console.log('HTTP/2 Server listening on https://localhost:8443');
});
```

---

## 4. HTTP Agent & Connection Pooling for Clients

When making outgoing HTTP requests to microservices, creating a new TCP connection on every request destroys throughput.

Use **`http.Agent`** to keep TCP sockets alive across requests (**HTTP Keep-Alive**):

```javascript
import http from 'node:http';

// Create persistent connection pool:
const keepAliveAgent = new http.Agent({
  keepAlive: true,
  maxSockets: 50,       // Max concurrent sockets per host
  maxFreeSockets: 10,   // Max idle sockets kept open in pool
  timeout: 60000,       // Active socket timeout
});

export function makePooledRequest(path) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: 'api.internal.service',
        port: 8080,
        path,
        method: 'GET',
        agent: keepAliveAgent, // ◄── Reuses existing open TCP sockets!
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => resolve(JSON.parse(data)));
      }
    );

    req.on('error', reject);
    req.end();
  });
}
```

---

## Troubleshooting & Best Practices

1. **`socket hang up` Errors**
   Ensure your backend `server.keepAliveTimeout` is higher than upstream reverse proxy timeouts (e.g. NGINX `keepalive_timeout 65s`). If Node closes a keep-alive socket while NGINX is routing a request, clients will receive a 502 Bad Gateway.

2. **Handle Stream `error` Events**
   In HTTP/2 and HTTP/1.1, always attach `stream.on('error', (err) => ...)` and `req.on('error', ...)` handlers. Unhandled stream errors will crash the entire Node process.
