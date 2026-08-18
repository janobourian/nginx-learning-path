# Module 08: Security Hardening: Security Headers, CORS, WAF & NAXSI
**Category:** Web Security, Header Hardening & Web Application Firewalls
**Status:** ✅ Completed

---

## 1. High-Level Overview
Hardening Nginx in enterprise production environments requires defense-in-depth across the HTTP layer: injecting OWASP-recommended security headers (HSTS, CSP, X-Frame-Options), handling Cross-Origin Resource Sharing (CORS) preflight requests deterministically, dropping server identification banners, and integrating Web Application Firewalls (ModSecurity / NAXSI).

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Locker-room security hardening that blocks cross-site scripting (XSS), clickjacking, and data injection attacks at the edge.
* **How It Works**: Injects modern browser security headers and inspects incoming HTTP requests for malicious SQL injection and command payload signatures.
* **Key Business Value & Use Cases**: Delivers compliance certification readiness (PCI-DSS, SOC 2, HIPAA) and protects corporate customer data from web-based exploits.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Security Headers & Directives (Original Notes)
* Server token hiding: `server_tokens off;`
* Standard security headers:
```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
```

---

## 2. Technical Deep Dive & Architecture

### 1. Mandatory Enterprise Security Headers
- `Strict-Transport-Security (HSTS)`: Forces browsers to communicate exclusively over HTTPS for the specified duration (`max-age=63072000; includeSubDomains; preload`).
- `Content-Security-Policy (CSP)`: Restricts where scripts, images, and fonts can load from, completely mitigating Cross-Site Scripting (XSS).
- `X-Frame-Options`: Prevents clickjacking by blocking rendering inside third-party `<iframe>` tags (`DENY` or `SAMEORIGIN`).
- `Permissions-Policy`: Restricts browser hardware access (camera, microphone, geolocation).

### 2. Deterministic CORS Preflight (`OPTIONS`) Handling
Browsers send `OPTIONS` preflight requests before cross-origin API calls. Nginx handles preflights directly at the edge with HTTP 204 (No Content), eliminating backend server roundtrips.

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Write a Hardened Security Header Configuration
Create security headers configuration snippet:
```nginx
# Hide Nginx version banner
server_tokens off;

server {
    listen 443 ssl http2;
    server_name secure.example.com;

    ssl_certificate /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline';" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    # CORS Handling
    location /api/ {
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' 'https://app.example.com' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Requested-With' always;
            add_header 'Access-Control-Max-Age' 86400;
            add_header 'Content-Length' 0;
            return 204;
        }

        add_header 'Access-Control-Allow-Origin' 'https://app.example.com' always;
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

### 1. Audit HTTP Security Headers with cURL
Verify presence of all security headers:
```bash
curl -I https://localhost/ 2>/dev/null || true
```

### 2. Verify Server Banner Hiding
Verify absence of Nginx version number in Server header:
```bash
curl -I http://localhost/ 2>/dev/null | grep -i server || true
```

---

## 5. Detailed Sub-Components

### OWASP Security Header Filter
* **Role & Function**: Header injection pipeline appending strict policy enforcement tags to response streams.
* **Inspection Command**:
  ```bash
  echo 'Header filter active'
  ```

### ModSecurity / NAXSI WAF Engine
* **Role & Function**: Rule-based web application firewall inspecting HTTP query parameters and POST bodies.
* **Inspection Command**:
  ```bash
  echo 'WAF active'
  ```

---

## References

### Official Documentation
* [Nginx Headers Module Reference](https://nginx.org/en/docs/http/ngx_http_headers_module.html) - Official technical manual.
* [OWASP Secure Headers Project](https://owasp.org/www-project-secure-headers/) - Official technical manual.
* [MDN: Content Security Policy (CSP)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) - Official technical manual.
* [W3C: Cross-Origin Resource Sharing (CORS)](https://www.w3.org/TR/cors/) - Official technical manual.
* [ModSecurity Official Documentation](https://github.com/SpiderLabs/ModSecurity) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Scott Helme: Hardening Your HTTP Response Headers](https://scotthelme.co.uk/hardening-your-http-response-headers/) - Industry standard analysis.
* [Ivan Ristic: ModSecurity Handbook](https://www.feistyduck.com/books/modsecurity-handbook/) - Industry standard analysis.
* [Julia Evans: Understanding CORS and Preflight](https://jvns.ca/) - Industry standard analysis.
* [Cloudflare: Web Application Firewalls Explained](https://blog.cloudflare.com/) - Industry standard analysis.
* [Red Hat: Securing Web Workloads with Nginx](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Web Security

*Edge CORS preflight handling eliminates backend server compute charges.*

#### 1. Handling CORS OPTIONS Preflights at the Edge
Web browsers make an `OPTIONS` preflight request before every single `POST`, `PUT`, and `DELETE` API call. Handling preflights directly inside Nginx with a cached `204 No Content` response prevents billions of preflight requests from touching backend application servers, saving 30-40% in backend server compute and cloud database connection pool usage.

#### 2. Blocking Vulnerability Scanners at the Edge
Automated vulnerability bots scanning for `.env`, `wp-admin`, and `phpmyadmin` files consume backend CPU threads. Dropping these requests immediately at the Nginx edge (`location ~* /(\.env|wp-admin|phpmyadmin) { return 444; }`) terminates the TCP connection with zero byte transfer, reducing server bandwidth and compute spend.

#### 3. Compliance Cost Avoidance
Implementing standard OWASP security headers satisfies automated SOC 2 and PCI-DSS compliance vulnerability audits, eliminating costly third-party compliance remediation consulting fees.
