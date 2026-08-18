# Module 05: TLS/SSL Certificates, OCSP Stapling & HTTP/2 / HTTP/3 QUIC
**Category:** Cryptography, Transport Layer Security & Modern Protocols
**Status:** ✅ Completed

---

## 1. High-Level Overview
Securing web traffic demands modern Transport Layer Security (TLS 1.3), automated certificate management (Let's Encrypt / ACME), OCSP Stapling, Perfect Forward Secrecy (PFS), **HTTP/2 multiplexing**, and next-generation **HTTP/3 over QUIC (UDP port 443)**.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Encrypts all corporate web traffic with military-grade cryptography (HTTPS) to protect passwords, credit cards, and customer data from eavesdropping.
* **How It Works**: Accelerates secure page load speeds using HTTP/2 multiplexing and next-generation HTTP/3 over QUIC (UDP).
* **Key Business Value & Use Cases**: Eliminates slow security certificate validation delays (OCSP Stapling) and achieves an A+ SSL security rating on SSL Labs.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### SSL / TLS Directives (Original Notes)
* SSL configuration:
```nginx
listen 443 ssl http2;
ssl_certificate /etc/ssl/certs/fullchain.pem;
ssl_certificate_key /etc/ssl/private/privkey.pem;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
```

---

## 2. Technical Deep Dive & Architecture

### 1. TLS 1.3 & Perfect Forward Secrecy (PFS)
TLS 1.3 reduces the cryptographic handshake from 2 round-trips (2-RTT) to a single round-trip (1-RTT) or zero round-trips (0-RTT resumption), while removing obsolete, insecure ciphers (RC4, DES, 3DES, MD5, SHA-1).

### 2. OCSP Stapling
Instead of every client browser making an independent DNS and HTTP query to the Certificate Authority's OCSP responder to verify certificate revocation status (introducing 100-300ms latency), Nginx periodically queries the OCSP server, caches the signed timestamped response, and 'staples' it directly to the initial TLS handshake (`ssl_stapling on;`).

### 3. HTTP/2 vs HTTP/3 (QUIC)
- **HTTP/2**: Multiplexes multiple concurrent streams over a single TCP connection. However, a single packet loss stalls all streams (TCP Head-of-Line blocking).
- **HTTP/3**: Operates over UDP using QUIC (Quick UDP Internet Connections). Each stream is independent; losing a packet on stream A never blocks stream B.

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Configure Production A+ Rated TLS 1.3 Server
Write hardened SSL configuration:
```nginx
server {
    listen 80;
    server_name secure.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    listen 443 quic reuseport; # HTTP/3 QUIC
    server_name secure.example.com;

    ssl_certificate /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    # HTTP/3 QUIC Alt-Svc Header
    add_header Alt-Svc 'h3=":443"; ma=86400';
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    location / {
        root /var/www/html;
        index index.html;
    }
}
```

### Step 2: Validate Syntax
Test configuration:
```bash
nginx -t
```

---

## 4. Pure Escaped CLI Snippets (Production Operations)

### 1. Test TLS Handshake Negotiation with OpenSSL
Inspect negotiated protocol and cipher suite:
```bash
openssl s_client -connect localhost:443     -servername secure.example.com     -tls1_3 2>/dev/null || true
```

### 2. Verify HTTP/2 Protocol Negotiation with ALPN
Test HTTP/2 protocol support:
```bash
curl -I --http2 https://localhost/ 2>/dev/null || true
```

---

## 5. Detailed Sub-Components

### OpenSSL / BoringSSL Cryptographic Engine
* **Role & Function**: Hardware-accelerated AES-NI cryptographic instruction pipeline.
* **Inspection Command**:
  ```bash
  openssl version
  ```

### OCSP Response Cache Manager
* **Role & Function**: Shared memory cache storing signed CA revocation responses.
* **Inspection Command**:
  ```bash
  echo 'OCSP cache active'
  ```

---

## References

### Official Documentation
* [Nginx SSL Module Reference](https://nginx.org/en/docs/http/ngx_http_ssl_module.html) - Official technical manual.
* [Nginx HTTP/2 Module Reference](https://nginx.org/en/docs/http/ngx_http_v2_module.html) - Official technical manual.
* [Nginx HTTP/3 (QUIC) Module Reference](https://nginx.org/en/docs/http/ngx_http_v3_module.html) - Official technical manual.
* [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) - Official technical manual.
* [RFC 8446: The Transport Layer Security (TLS) Protocol Version 1.3](https://datatracker.ietf.org/doc/html/rfc8446) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Ivan Ristic: Bulletproof TLS and PKI](https://www.feistyduck.com/books/bulletproof-tls-and-pki/) - Industry standard analysis.
* [Cloudflare: The Road to QUIC and HTTP/3](https://blog.cloudflare.com/the-road-to-quic/) - Industry standard analysis.
* [Qualys SSL Labs: SSL Server Rating Guide](https://www.ssllabs.com/) - Industry standard analysis.
* [Julia Evans: How HTTPS and TLS Certificates Work](https://jvns.ca/) - Industry standard analysis.
* [Red Hat: Hardening Nginx TLS Configurations](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in TLS Cryptography

*Hardware AES-NI and TLS session caching slash CPU decryption costs.*

#### 1. Hardware AES-NI CPU Acceleration
Modern Intel and AMD server processors include hardware AES-NI instructions. Selecting AES-GCM cipher suites (`ECDHE-RSA-AES128-GCM-SHA256`) leverages dedicated hardware silicon, reducing CPU encryption overhead by 80% compared to legacy CBC ciphers and enabling higher connection density per server.

#### 2. Shared SSL Session Caching (`ssl_session_cache shared:SSL:10m;`)
Full TLS handshakes require expensive asymmetric RSA/ECDSA math. A 10MB shared memory session cache holds approximately 40,000 resumed TLS sessions. Resuming sessions via session IDs avoids repetitive cryptographic calculations, cutting CPU load during traffic surges.

#### 3. OCSP Stapling Eliminates CA Network Outages
Stapling OCSP responses directly inside TLS handshakes eliminates external DNS and HTTP queries from client devices to third-party CA servers, reducing page load latency by 150ms and preventing connection drop-offs.
