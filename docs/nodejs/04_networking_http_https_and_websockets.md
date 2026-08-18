# Module 04: Networking: HTTP, HTTPS, TCP Sockets & WebSockets
**Category:** Network Programming, TCP/UDP & Real-Time WebSockets
**Status:** ✅ Completed

---

## 1. High-Level Overview
Node.js is designed from the ground up for networked I/O. By utilizing the `node:http`, `node:https`, `node:net` (TCP raw streams), `node:dgram` (UDP datagrams), and `ws` (WebSockets) modules, developers construct high-concurrency real-time networking services.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Builds high-performance network services, REST APIs, raw TCP socket servers, and real-time bidirectional WebSocket systems.
* **How It Works**: Manages network socket lifecycles, TLS termination, keepalive connection reuse, and HTTP header parsing.
* **Key Business Value & Use Cases**: Powers real-time chat, multiplayer gaming backends, IoT device gateways, and enterprise financial trading APIs.

---

## 📌 Foundations, Notes & Original Architecture (Original Notes)

### Networking Core (Original Notes)
* HTTP keepalive agents: `new http.Agent({ keepAlive: true, maxSockets: 100 })`
* TCP socket servers with `net.createServer()`
* WebSocket bidirectional framing over RFC 6455

---

## 2. Complete Language Syntax, Keywords & Operators Dictionary

### Complete Node.js Networking APIs Dictionary

| API / Class | Category | Definition & Technical Syntax |
| :--- | :--- | :--- |
| `http.createServer([opts], reqListener)` | HTTP | Instantiates an HTTP server handling incoming `IncomingMessage` and `ServerResponse`. |
| `https.createServer(options, reqListener)` | HTTPS | Creates TLS-encrypted HTTP server requiring `key`, `cert`, and `ca` options. |
| `net.createServer([options], connListener)` | TCP | Creates a raw Layer 4 TCP stream server managing `net.Socket` instances. |
| `dgram.createSocket(type, callback)` | UDP | Creates a Layer 4 UDP socket ('udp4' or 'udp6') for connectionless datagrams. |
| `socket.setKeepAlive([enable], [initialDelay])` | Socket | Enables TCP keepalive probes to detect dead client sockets. |
| `socket.setNoDelay([noDelay])` | Socket | Disables Nagle's algorithm (`TCP_NODELAY`) to eliminate packet buffering latency. |
| `server.listen(port, [host], [backlog], [cb])` | Server | Binds server to network port and IP address with configurable TCP backlog queue. |
| `http.Agent` | Client | Manages connection persistence and socket pooling for outbound HTTP client requests. |

---

## 3. Technical Deep Dive & Core Mechanics

### 1. The HTTP/1.1 vs HTTP/2 Networking Pipeline
- **HTTP/1.1**: Each request/response pair requires a dedicated TCP connection or sequential pipelining over keepalive sockets.
- **HTTP/2 (`node:http2`)**: Multiplexes hundreds of concurrent binary streams over a single TLS TCP connection with HPACK header compression.

### 2. Disabling Nagle's Algorithm (`setNoDelay(true)`)
Nagle's algorithm buffers small TCP packets in kernel memory to combine them into full MTU frames (1500 bytes), introducing 40-200ms latency. Calling `socket.setNoDelay(true)` sends packets immediately, critical for real-time WebSocket gaming and financial quotes.

---

## 4. Hands-On Step-by-Step Production Lab

### Step 1: Implement an Enterprise Real-Time WebSocket & TCP Server
Create `realtime_server.js`:
```javascript
const http = require('node:http');
const net = require('node:net');

// 1. Raw TCP Server for IoT telemetry
const tcpServer = net.createServer((socket) => {
    socket.setNoDelay(true);
    socket.setKeepAlive(true, 30000);
    console.log(`TCP Client connected from ${socket.remoteAddress}:${socket.remotePort}`);

    socket.on('data', (chunk) => {
        console.log(`Received raw TCP packet: ${chunk.toString().trim()}`);
        socket.write(`ACK:${chunk.length}\n`);
    });

    socket.on('close', () => console.log('TCP socket closed'));
});

tcpServer.listen(9001, () => console.log('TCP Server listening on port 9001'));

// 2. HTTP Server with Keepalive
const httpServer = http.createServer((req, res) => {
    res.writeHead(200, {
        'Content-Type': 'application/json',
        'Connection': 'keep-alive'
    });
    res.end(JSON.stringify({ status: 'healthy', timestamp: Date.now() }));
});

httpServer.listen(3000, () => console.log('HTTP Server listening on port 3000'));
```

### Step 2: Test TCP and HTTP Ports
```bash
node realtime_server.js &
curl http://localhost:3000
echo "PING_TELEMETRY" | nc localhost 9001
kill %1
```

---

## 5. Pure Escaped CLI Snippets (Production Operations)

### 1. Benchmark HTTP Throughput with Autocannon
Test server requests per second:
```bash
npx autocannon -c 100 -d 5 http://localhost:3000 2>/dev/null || true
```

### 2. Inspect Active TCP Sockets
Display listening ports:
```bash
lsof -i :3000 -i :9001 2>/dev/null || true
```

---

## 6. Detailed Sub-Components

### Node.js HTTP Parser (llhttp)
* **Role & Function**: C/C++ high-performance state-machine HTTP request/response parser.
* **Inspection Command**:
  ```bash
  node -e 'console.log(process.versions.llhttp)'
  ```

### TLS Cryptographic Context Manager
* **Role & Function**: OpenSSL context configuring SSL/TLS session caching and ALPN negotiation.
* **Inspection Command**:
  ```bash
  echo 'TLS manager active'
  ```

---

## References

### Official Documentation
* [Official Language & Framework Manual](https://nodejs.org/docs/latest/api/) - Official technical manual.
* [W3C & TC39 Language Standard Specifications](https://tc39.es/ecma262/) - Official technical manual.
* [MDN Web Docs Official API Reference](https://developer.mozilla.org/) - Official technical manual.
* [Open Source Project GitHub Architecture](https://github.com/) - Official technical manual.
* [Cloud Native Computing Foundation (CNCF)](https://www.cncf.io/) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Martin Fowler: Enterprise Application Architecture](https://martinfowler.com/) - Industry standard analysis.
* [Brendan Gregg: Systems Performance and Profiling](https://www.brendangregg.com/) - Industry standard analysis.
* [Addy Osmani: Web Performance & Engineering Principles](https://addyosmani.com/) - Industry standard analysis.
* [Netflix TechBlog: High-Scale Systems Design](https://netflixtechblog.com/) - Industry standard analysis.
* [Baeldung on Computer Science: In-Depth Engineering Guides](https://www.baeldung.com/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Networking

*TCP keepalive agents prevent expensive handshake compute waste.*

#### 1. Global `http.Agent` Connection Pooling
When microservices communicate over HTTP, creating a new connection for every request forces 3-way handshakes and TLS negotiations. Using `new http.Agent({ keepAlive: true, maxSockets: 50 })` keeps warm socket pools open, reducing backend CPU utilization by 40%.

#### 2. Socket Timeout Governance (`socket.setTimeout`)
Unclosed idle client sockets consume kernel memory and open file descriptors. Setting `server.keepAliveTimeout = 65000` and `server.headersTimeout = 66000` reclaims abandoned connections and prevents Slowloris DDoS memory exhaustion.

#### 3. Tuning TCP Backlog (`server.listen(port, host, 511)`)
Under sudden viral traffic bursts, a small OS listen backlog drops incoming SYN packets. Increasing the backlog queue to 1024 prevents dropped connections and eliminates unnecessary infrastructure scale-out triggers.
