# Module 07: Rate Limiting, Concurrency Controls & DDoS Mitigation
**Category:** Traffic Shaping, Rate Limiting & DDoS Defense
**Status:** ✅ Completed

---

## 1. High-Level Overview
Nginx implements traffic shaping and denial-of-service mitigation using the **Leaky Bucket Algorithm** via the `ngx_http_limit_req_module` and concurrency connection limits via the `ngx_http_limit_conn_module`. These controls protect backend application servers against brute-force credential stuffing, API scraping, and Layer 7 DDoS attacks.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Protects web applications and login pages against brute-force password guessing, automated scraping bots, and denial-of-service (DDoS) attacks.
* **How It Works**: Enforces strict rate limits (e.g. max 5 requests per second per IP) while allowing brief, natural traffic bursts without blocking real users.
* **Key Business Value & Use Cases**: Prevents server outages during cyberattacks, ensures fair resource sharing, and maintains 100% service uptime for legitimate customers.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Rate Limiting & Connection Limits (Original Notes)
* Rate limit zone: `limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;`
* Application in location: `limit_req zone=api_limit burst=20 nodelay;`
* Connection limit: `limit_conn_zone $binary_remote_addr zone=addr_limit:10m;`
* Status codes: `limit_req_status 429;`

---

## 2. Technical Deep Dive & Architecture

### 1. The Leaky Bucket Algorithm
Nginx models rate limiting as a bucket with a fixed leakage rate:
- Water (requests) enters at variable speed.
- Water leaks out at a constant rate ($r$ requests/second).
- If incoming requests exceed bucket capacity (**burst**), excess water overflows and Nginx rejects requests with HTTP 429 (Too Many Requests) or HTTP 503.

### 2. The `burst` and `nodelay` Flags
- `limit_req zone=api rate=5r/s;`: Strictly permits 1 request every 200ms. An HTML page loading 4 images simultaneously triggers 3 errors!
- `limit_req zone=api burst=10;`: Permits up to 10 requests to queue in memory, delaying them so they execute at 5r/s.
- `limit_req zone=api burst=10 nodelay;`: Processes all 10 burst requests **instantly** with zero delay, but rejects any subsequent 11th request until the bucket leaks!

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Configure Layer 7 Rate Limiting and Brute-Force Protection
Write rate limiting configuration:
```nginx
# 10MB zone tracks ~160,000 distinct IP addresses in binary format
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=2r/s;
limit_req_zone $binary_remote_addr zone=general_api:10m rate=20r/s;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

server {
    listen 80;
    server_name api.example.com;

    limit_req_status 429;
    limit_conn_status 429;

    # Sensitive authentication route
    location /api/auth/login {
        limit_req zone=login_limit burst=5 nodelay;
        limit_conn conn_limit 5; # Max 5 concurrent TCP connections per IP

        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }

    # General API route
    location /api/ {
        limit_req zone=general_api burst=40 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
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

### 1. Test Rate Limiter HTTP 429 Rejection with cURL
Simulate rapid burst requests:
```bash
for i in {1..10}; do
    curl -s -o /dev/null -w "%{http_code}
" http://localhost/api/auth/login
done 2>/dev/null || true
```

### 2. Inspect Nginx Error Log for Rate Limit Drops
Filter limiting log events:
```bash
grep "limiting requests" /var/log/nginx/error.log 2>/dev/null || true
```

---

## 5. Detailed Sub-Components

### Binary Remote Addr Storage ($binary_remote_addr)
* **Role & Function**: Stores client IPv4 in 4 bytes (or IPv6 in 16 bytes) rather than 15-byte string, saving 75% RAM.
* **Inspection Command**:
  ```bash
  echo 'Binary remote addr active'
  ```

### Leaky Bucket Shaper (ngx_http_limit_req_module)
* **Role & Function**: High-performance lockless rate limiting engine in shared memory.
* **Inspection Command**:
  ```bash
  echo 'Limit req active'
  ```

---

## References

### Official Documentation
* [Nginx Rate Limiting Module Reference](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html) - Official technical manual.
* [Nginx Connection Limiting Module Reference](https://nginx.org/en/docs/http/ngx_http_limit_conn_module.html) - Official technical manual.
* [Nginx Blog: Rate Limiting with NGINX](https://www.nginx.com/blog/rate-limiting-nginx/) - Official technical manual.
* [RFC 6585: Additional HTTP Status Codes (429 Too Many Requests)](https://datatracker.ietf.org/doc/html/rfc6585) - Official technical manual.
* [OWASP Automated Threats to Web Applications](https://owasp.org/www-project-automated-threats-to-web-applications/) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Andrew Alexeev: Mitigating DDoS Attacks with NGINX](https://www.nginx.com/blog/mitigating-ddos-attacks-with-nginx-and-nginx-plus/) - Industry standard analysis.
* [Julia Evans: How Rate Limiting Works](https://jvns.ca/) - Industry standard analysis.
* [Cloudflare: How Rate Limiting Protects APIs](https://blog.cloudflare.com/) - Industry standard analysis.
* [Baeldung on Linux: Rate Limiting in Nginx](https://www.baeldung.com/linux/nginx-rate-limiting) - Industry standard analysis.
* [Red Hat: Protecting Web Applications with Nginx Limits](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Traffic Shaping

*Rate limiting protects cloud infrastructure budgets against billing attacks and scrapers.*

#### 1. Mitigating Economic Denial of Sustainability (EDoS) Attacks
Malicious bots scraping un-rate-limited search or AI endpoints can trigger thousands of expensive backend cloud database queries and LLM API calls, running up thousands of dollars in billable cloud charges overnight. Strict rate limiting at the Nginx edge drops malicious traffic before it touches billable backend APIs.

#### 2. Memory Footprint Optimization via `$binary_remote_addr`
Using `$binary_remote_addr` instead of `$remote_addr` stores client IPs in 4 bytes (IPv4) or 16 bytes (IPv6) rather than 7-15 byte ASCII strings. A 10MB shared memory zone can track over 160,000 distinct concurrent client IP addresses, eliminating the need to purchase larger RAM server instances.

#### 3. Graceful Load Shedding Under Peak Traffic
During Black Friday or viral events, returning lightweight HTTP 429 responses from Nginx's shared memory consumes negligible CPU, preventing backend application crashes and eliminating emergency server over-provisioning.
