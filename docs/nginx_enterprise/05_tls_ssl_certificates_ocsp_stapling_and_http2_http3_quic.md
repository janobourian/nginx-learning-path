# Module 05: TLS/SSL Certificates, OCSP Stapling, HTTP/2 & HTTP/3 QUIC

**Track:** Enterprise NGINX  
**Category:** Transport Security & Protocol Optimization

---

## Why TLS Matters and What It Actually Does

When a browser connects to your site over HTTPS, TLS (Transport Layer Security) does three things: it **authenticates** that your server is who it claims to be (via a certificate signed by a Certificate Authority), it **encrypts** the data so no one on the path can read it, and it **ensures integrity** so no one can tamper with the data in transit without detection.

The practical performance concern with TLS is the **handshake cost**. A full TLS 1.3 handshake requires one round trip between client and browser before any HTTP data flows. On a 100ms latency connection, that's 100ms of pure overhead before a single byte of your page arrives.

NGINX addresses this through: session resumption (reusing previous handshakes), OCSP stapling (eliminating a CA lookup), HTTP/2 multiplexing (reusing one TLS connection for many requests), and eventually HTTP/3 QUIC (eliminating TCP entirely).

---

## TLS Configuration: The Correct Modern Baseline

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name example.com;

    # ── Certificate chain ──────────────────────────────────────────────────
    # fullchain.pem contains your certificate + intermediate CA certificates
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # ── Protocol versions ──────────────────────────────────────────────────
    # TLS 1.0 and 1.1 are deprecated (RFC 8996). Never enable them.
    ssl_protocols TLSv1.2 TLSv1.3;

    # ── Cipher suites ──────────────────────────────────────────────────────
    # TLS 1.3 ciphers are not configurable — the browser and server negotiate
    # automatically. These suites apply only to TLS 1.2 fallback connections.
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    # ── Session resumption ─────────────────────────────────────────────────
    # Shared across all NGINX workers so returning clients skip the full handshake
    ssl_session_cache   shared:SSL:10m;   # 10MB stores ~40,000 sessions
    ssl_session_timeout 1d;

    # ── OCSP Stapling ──────────────────────────────────────────────────────
    ssl_stapling        on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # ── HSTS ───────────────────────────────────────────────────────────────
    # Instructs browsers to only connect via HTTPS for the next 2 years
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
}
```

---

## Understanding OCSP Stapling

When a browser receives your certificate, it needs to verify that the certificate hasn't been revoked. Normally it contacts the Certificate Authority's **OCSP responder** to ask. This adds a DNS lookup + network round trip to the first connection.

**OCSP Stapling** moves this lookup to your NGINX server. NGINX fetches the OCSP response from the CA periodically (cached via the `resolver`), then "staples" it to the TLS handshake response. The browser gets proof of validity instantly, with no extra round trip.

```bash
# Verify OCSP stapling is working
openssl s_client \
    -connect example.com:443 \
    -servername example.com \
    -status \
    </dev/null 2>/dev/null \
    | grep -A 10 "OCSP Response"
```

Output confirming it works:
```
OCSP Response Status: successful (0x0)
This Update: Aug 18 00:00:00 2026 GMT
Next Update: Aug 25 00:00:00 2026 GMT
```

---

## HTTP/2: What Changes and Why It Matters

HTTP/1.1 sends one request per TCP connection at a time. Even with pipelining, head-of-line blocking means a slow response blocks all subsequent responses. Browsers work around this by opening 6-8 parallel TCP connections per domain — creating overhead.

HTTP/2 solves this with **multiplexing**: multiple request/response pairs share a single TCP connection as independent **streams**. A slow stream does not block fast ones. This allows browsers to use a single connection per origin.

```nginx
server {
    listen 443 ssl;
    http2 on;        # Enable HTTP/2 (NGINX 1.25.1+)
    server_name example.com;
    # All other configuration stays identical
}
```

HTTP/2 also adds **header compression** (HPACK) which shrinks the repetitive headers browsers send on every request (User-Agent, cookies, Accept-Encoding) by 40-80%.

```bash
# Confirm HTTP/2 is working
curl -I --http2 https://example.com 2>&1 | grep "HTTP/"
# Should output: HTTP/2 200
```

---

## HTTP/3 QUIC: Eliminating TCP

HTTP/3 runs over **QUIC**, a transport protocol built on UDP instead of TCP. QUIC provides the reliability of TCP (retransmission, ordering) without TCP's head-of-line blocking at the transport layer. It also builds TLS 1.3 directly into the protocol, reducing connection establishment from 2 round trips (TCP SYN + TLS) to 1.

NGINX 1.25.0+ includes experimental QUIC/HTTP/3 support:

```nginx
server {
    # TCP port for HTTP/1.1 and HTTP/2
    listen 443 ssl;
    http2 on;

    # UDP port for QUIC/HTTP/3
    listen 443 quic reuseport;

    server_name example.com;

    ssl_certificate     /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;
    ssl_protocols       TLSv1.3;

    # Tell browsers this server supports HTTP/3 on port 443
    add_header Alt-Svc 'h3=":443"; ma=86400';
}
```

The `Alt-Svc` header tells browsers: "I support HTTP/3 on port 443. Cache this fact for 86400 seconds (1 day)." On subsequent visits the browser connects via QUIC directly.

QUIC requires UDP port 443 to be open in your firewall. Many corporate firewalls block UDP 443, so HTTP/2 over TCP remains essential as the fallback.

---

## Let's Encrypt Certificate Automation

```bash
# Install Certbot with NGINX plugin
apt-get install -y certbot python3-certbot-nginx

# Obtain certificate and auto-configure NGINX
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email admin@example.com \
    -d example.com \
    -d www.example.com

# Test automatic renewal
certbot renew --dry-run

# Certbot installs a systemd timer for renewal — verify it's active
systemctl status certbot.timer

# Check certificate expiry
certbot certificates
```

The NGINX plugin automatically modifies your server block to add TLS configuration and adds a renewal hook that runs `nginx -s reload` after certificate renewal.

---

## dhparam for TLS 1.2 Diffie-Hellman Key Exchange

For TLS 1.2 DHE cipher suites, NGINX uses Diffie-Hellman parameters. The default OpenSSL parameters are 1024-bit which is weak. Generate strong 2048-bit parameters:

```bash
# Generate 2048-bit DH parameters (takes 1-2 minutes)
openssl dhparam -out /etc/nginx/dhparam.pem 2048
```

```nginx
ssl_dhparam /etc/nginx/dhparam.pem;
```

This is only necessary if you support DHE cipher suites for TLS 1.2. ECDHE cipher suites (which are preferred and listed first in `ssl_ciphers`) do not use dhparam.

---

## Testing TLS Configuration Quality

```bash
# Comprehensive TLS analysis (grade A+ is the target)
# Run from your server or use ssllabs.com
openssl s_client \
    -connect example.com:443 \
    -servername example.com \
    </dev/null 2>/dev/null \
    | openssl x509 -noout -text \
    | grep -E "Subject:|Issuer:|Not Before:|Not After:|Signature Algorithm:"

# Check which TLS version is negotiated
curl -v --tlsv1.3 https://example.com 2>&1 | grep "SSL connection"

# Verify HSTS header is present
curl -I https://example.com | grep Strict-Transport

# Test that TLS 1.0/1.1 are rejected
openssl s_client -connect example.com:443 -tls1 </dev/null 2>&1 | grep "handshake failure"
```

---

## FinOps Considerations

OCSP stapling eliminates one network round trip to the CA on every new TLS session. At 10,000 new connections/minute, that is 10,000 avoided HTTP requests to the CA per minute. Beyond latency reduction, CA OCSP responders sometimes have rate limits or geographic latency — OCSP stapling makes your TLS independent of CA availability.

HTTP/2 header compression (HPACK) reduces header sizes by 60-80% on typical API traffic. For a mobile API receiving 50-byte JSON payloads, but 800-byte cookie and header blocks, this compression has more impact on bandwidth costs than gzip on the response body.

---

## Troubleshooting TLS Issues

**Error: `SSL_CTX_use_certificate_file() failed` on startup**

The `ssl_certificate` path points to your leaf certificate only, not the full chain. Let's Encrypt provides `cert.pem` (leaf only) and `fullchain.pem` (leaf + intermediates). Always use `fullchain.pem` for `ssl_certificate`.

**Error: `no "ssl_certificate" is defined` in NGINX logs**

You have `listen 443 ssl` but no `ssl_certificate`/`ssl_certificate_key` directives in that server block. Both are required. Verify them with `nginx -T | grep ssl_certificate`.

**Browser shows certificate warning despite valid certificate**

The certificate chain is incomplete. The server is sending only the leaf certificate. Confirm by running:
```bash
openssl s_client -connect example.com:443 -showcerts </dev/null 2>/dev/null | grep "BEGIN CERT" | wc -l
```
Should output 2 or 3 (leaf + one or two intermediate CAs). If it outputs 1, the `ssl_certificate` file is missing the intermediate chain. Use `fullchain.pem`.
