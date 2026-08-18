# Module 05: HTTP/1.1, HTTP/2 & HTTP/3 QUIC Internals

**Track:** Modern JavaScript — Backend Systems & Distributed Architecture  
**Category:** Networking Protocols, HTTP/2 Multiplexing & HTTP/3 QUIC

---

## 1. The Protocol Evolution: HTTP/1.1 ──► HTTP/2 ──► HTTP/3

```
┌─────────────────────────────────────────────────────────────┐
│                 HTTP Protocol Architecture Matrix           │
├───────────────────┬──────────────────┬──────────────────────┤
│ Feature           │ HTTP/1.1         │ HTTP/2               │ HTTP/3               │
├───────────────────┼──────────────────┼──────────────────────┤
│ **Transport**     │ TCP              │ TCP                  │ **QUIC (over UDP)**  │
│ **Framing**       │ Plaintext        │ Binary Framing       │ Binary Framing       │
│ **Multiplexing**  │ No (HoL Blocking)│ **Yes (Single TCP)** │ **Yes (QUIC Streams)│
│ **TCP HoL Block** │ Severe           │ Exists at TCP layer  │ **ELIMINATED!**      │
│ **TLS Handshake** │ 1-2 RTT          │ 1-2 RTT              │ **0-RTT Resumption** │
│ **Connection**    │ Reconnects on IP │ Reconnects on IP     │ **Seamless IP        │
│ **Migration**     │ change           │ change               │ Migration (WiFi->5G)│
└───────────────────┴──────────────────┴──────────────────────┘
```

---

## 2. HTTP/2 Binary Framing & Multiplexing

HTTP/2 decomposes requests and responses into small binary **Frames** (HEADERS, DATA, SETTINGS, PING, RST_STREAM), multiplexing independent streams over a single TCP connection:

```
HTTP/2 Multiplexed Frame Interleaving:
[Single TCP Socket] ──► [Stream 1: Headers] [Stream 2: Data] [Stream 1: Data] [Stream 3: Headers] ──►
```

### Implementing HTTP/2 with Server Push in Node.js:

```javascript
// src/servers/http2_streamer.js
import http2 from 'node:http2';
import fs from 'node:fs';

const server = http2.createSecureServer({
  key: fs.readFileSync('certs/key.pem'),
  cert: fs.readFileSync('certs/cert.pem'),
});

server.on('stream', (stream, headers) => {
  const path = headers[':path'];

  if (path === '/stream-data') {
    // 1. Send HTTP/2 Response Headers:
    stream.respond({
      ':status': 200,
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-cache',
    });

    let counter = 0;
    // 2. Stream chunked frames over HTTP/2 stream:
    const interval = setInterval(() => {
      counter++;
      const payload = JSON.stringify({ tick: counter, time: Date.now() }) + '\n';
      stream.write(payload);

      if (counter >= 10) {
        clearInterval(interval);
        stream.end(); // Close stream cleanly
      }
    }, 500);

    stream.on('close', () => clearInterval(interval));
    return;
  }

  stream.respond({ ':status': 404 });
  stream.end('Not Found');
});

server.listen(8443, () => console.log('HTTP/2 Server listening on port 8443'));
```

---

## 3. Deep Dive into HTTP/3 & QUIC

While HTTP/2 solved application-level Head-of-Line blocking, it still suffered from **TCP-level Head-of-Line blocking**:
- If a single TCP packet was dropped over spotty cellular networks, the entire TCP connection was paused while retransmitting that packet, blocking all 100 multiplexed streams simultaneously!

### How HTTP/3 & QUIC Solve This:
1. **QUIC over UDP**: QUIC implements reliable transmission directly in userland over UDP. Each stream is **completely independent**: if a packet in Stream 1 is lost, **Streams 2 through 100 continue streaming without pause!**
2. **0-RTT Connection Resumption**: Clients that previously connected can send encrypted application data on the very first round-trip packet.
3. **Connection ID & Migration**: QUIC identifies connections via a unique 64-bit **Connection ID** (not IP:Port). When a user walks out of their house and their phone switches from WiFi to 5G, active video downloads and downloads **continue without dropping the connection!**

---

## Troubleshooting & Best Practices

1. **Enable ALPN (Application-Layer Protocol Negotiation)**
   When configuring TLS certificates for HTTP/2 and HTTP/3, configure `ALPNProtocols: ['h2', 'http/1.1']` so that clients negotiate the fastest supported protocol during the TLS handshake.

2. **Server Push Deprecation**
   Modern browsers have deprecated HTTP/2 Server Push in favor of `<link rel="preload">` and 103 Early Hints, which allow browser caches to be respected before downloading assets.
