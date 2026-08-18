# Module 08: Security Hardening, HTTP Headers, CORS & WAF with NAXSI

**Track:** Enterprise NGINX  
**Category:** Web Application Security

---

## Security at the HTTP Layer

NGINX sits at the boundary between the internet and your application. This position makes it the ideal place to enforce security policies that protect against the most common web attacks: clickjacking, MIME sniffing, cross-site scripting, cross-origin data theft, and injection attacks.

Most of these defenses are implemented by adding or controlling **HTTP response headers**. Browsers read these headers and enforce restrictions on what the page can do.

---

## Essential Security Response Headers

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    # ── Clickjacking Protection ────────────────────────────────────────────
    # Prevents your page from being embedded in an <iframe> on another domain
    # SAMEORIGIN: allow your own domain to iframe you; DENY: nobody can
    add_header X-Frame-Options "SAMEORIGIN" always;

    # ── MIME Sniffing Protection ───────────────────────────────────────────
    # Prevents browsers from guessing the content type of a response.
    # Without this, a browser might execute a text/plain file as JavaScript
    # if it looks like JS — a common XSS vector.
    add_header X-Content-Type-Options "nosniff" always;

    # ── Referrer Policy ───────────────────────────────────────────────────
    # Controls how much URL information is sent in the Referer header
    # when a user navigates from your page to another site.
    # strict-origin-when-cross-origin: full URL for same-origin,
    #   only origin (no path/query) for cross-origin HTTPS → HTTPS,
    #   nothing for HTTPS → HTTP transitions.
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # ── Permissions Policy (formerly Feature Policy) ───────────────────────
    # Disable browser features your app does not use.
    # This prevents a compromised script from accessing geolocation, camera, etc.
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;

    # ── Content Security Policy ───────────────────────────────────────────
    # The most powerful XSS defense. Declares exactly which sources are allowed
    # to load scripts, styles, images, fonts, and connections.
    # This policy is strict — adjust based on your actual CDN/font/analytics sources.
    add_header Content-Security-Policy
        "default-src 'self'; "
        "script-src 'self' https://cdn.example.com; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "img-src 'self' data: https:; "
        "connect-src 'self' https://api.example.com; "
        "frame-ancestors 'none'; "
        "upgrade-insecure-requests;"
        always;

    # ── HSTS (HTTP Strict Transport Security) ─────────────────────────────
    # Tells browsers to always use HTTPS for this domain for the next 2 years.
    # includeSubDomains: applies to all subdomains too.
    # preload: allows submission to browser HSTS preload lists.
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # ── Remove server version disclosure ──────────────────────────────────
    # By default NGINX sends "Server: nginx/1.25.3" — a fingerprinting aid for attackers
    server_tokens off;
}
```

The `always` parameter ensures headers are added even for error responses (4xx, 5xx). Without it, headers are only added to 2xx responses, leaving error pages unprotected.

---

## CORS: Cross-Origin Resource Sharing

When your frontend at `app.example.com` makes an AJAX call to your API at `api.example.com`, the browser's **same-origin policy** blocks the request unless the API explicitly allows it via CORS headers.

```nginx
# /etc/nginx/snippets/cors.conf

# The origin is set dynamically so you can allow multiple specific origins
# rather than using the wildcard * (which prevents cookies from being sent)
map $http_origin $cors_origin {
    default                    "";
    "https://app.example.com"  "https://app.example.com";
    "https://admin.example.com" "https://admin.example.com";
    "http://localhost:3000"    "http://localhost:3000";  # Local development
}

server {
    listen 443 ssl;
    server_name api.example.com;

    location /api/ {
        # Handle preflight OPTIONS request
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin  $cors_origin;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, PATCH, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With, X-API-Key";
            add_header Access-Control-Allow-Credentials "true";
            add_header Access-Control-Max-Age 3600;  # Cache preflight for 1 hour
            add_header Content-Length 0;
            return 204;
        }

        # Add CORS headers to actual requests
        add_header Access-Control-Allow-Origin      $cors_origin always;
        add_header Access-Control-Allow-Credentials "true" always;
        add_header Vary "Origin" always;  # Tell caches that responses vary by Origin

        proxy_pass http://backend_api;
    }
}
```

The `Vary: Origin` header is critical. Without it, a caching proxy might store the response with one origin's CORS headers and serve it to a request from a different origin — causing CORS failures for users or leaking credentials across origins.

---

## Hiding Sensitive Information

```nginx
server {
    # Remove NGINX version from Server header
    server_tokens off;

    # Remove X-Powered-By if your backend sends it (Node.js, PHP)
    proxy_hide_header X-Powered-By;

    # Remove internal infrastructure headers the backend sends
    proxy_hide_header X-Internal-Server;
    proxy_hide_header X-Debug-Info;

    # Rewrite Location headers from backend to use external hostname
    # (Prevents internal IPs from leaking in 301/302 responses)
    proxy_redirect http://10.0.0.1:3000 https://api.example.com;
}
```

---

## WAF with NAXSI (NGINX Anti-XSS & SQL Injection)

NAXSI is an open-source WAF module for NGINX that blocks common attack patterns using a rule set. Unlike signature-based WAFs, NAXSI uses a **scoring system**: each rule adds to a score, and a request is blocked only when the total score crosses a threshold.

Installation (from source with NAXSI):

```bash
# NAXSI must be compiled into NGINX
apt-get install -y nginx-naxsi

# Or compile from source with module
./configure --add-module=/path/to/naxsi/naxsi_src --with-http_ssl_module
make && make install
```

NAXSI configuration:

```nginx
# /etc/nginx/naxsi_core.rules
# The core rules file from the NAXSI repository
# Contains patterns for SQL injection, XSS, file inclusion, etc.

# /etc/nginx/conf.d/naxsi.conf

server {
    listen 443 ssl;
    server_name api.example.com;

    location /api/ {
        # Include NAXSI core rules
        include /etc/nginx/naxsi_core.rules;

        # Request exceeds this score → block with 403
        DeniedUrl "/naxsi_blocked";

        # Score thresholds per attack category
        CheckRule "$SQL >= 8" BLOCK;
        CheckRule "$RFI >= 8" BLOCK;
        CheckRule "$TRAVERSAL >= 4" BLOCK;
        CheckRule "$EVADE >= 4" BLOCK;
        CheckRule "$XSS >= 8" BLOCK;

        proxy_pass http://backend;
    }

    # Block response page
    location /naxsi_blocked {
        return 403 '{"error":"request_blocked","message":"Potentially malicious request detected."}';
    }
}
```

**NAXSI Learning Mode**: Before enabling blocking, run in learning mode (replace `BLOCK` with `LOG`) to identify false positives. NAXSI logs blocked requests to `error.log` with the matched rule IDs, which you whitelist.

```nginx
# Learning mode — logs but does not block
LearningMode;
SecRulesEnabled;
DeniedUrl "/naxsi_blocked";
CheckRule "$SQL >= 8" LOG;
```

---

## ModSecurity WAF (Alternative to NAXSI)

ModSecurity with the OWASP Core Rule Set (CRS) is the most widely deployed open-source WAF:

```bash
# Install ModSecurity NGINX connector
apt-get install -y libmodsecurity3 libmodsecurity-dev

# Download OWASP CRS
git clone https://github.com/coreruleset/coreruleset.git /etc/modsecurity/crs
cp /etc/modsecurity/crs/crs-setup.conf.example /etc/modsecurity/crs/crs-setup.conf
```

```nginx
# /etc/nginx/modsec/modsecurity.conf (main config)
SecRuleEngine On          # DetectionOnly to log without blocking
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml application/json

# Include OWASP CRS rules
Include /etc/modsecurity/crs/crs-setup.conf
Include /etc/modsecurity/crs/rules/*.conf
```

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsec/modsecurity.conf;

    location / {
        proxy_pass http://backend;
    }
}
```

---

## CLI: Checking Security Headers

```bash
# Verify all security headers are present
curl -I https://example.com | grep -E "X-Frame|X-Content|Strict-Transport|Content-Security|Referrer|Permissions"

# Automated security header grade
# Use securityheaders.com API or scan locally
curl -s "https://securityheaders.com/?q=https://example.com&followRedirects=on" | grep "Grade"

# Check CORS preflight response
curl -v \
    -X OPTIONS \
    -H "Origin: https://app.example.com" \
    -H "Access-Control-Request-Method: POST" \
    -H "Access-Control-Request-Headers: Authorization" \
    https://api.example.com/api/users 2>&1 \
    | grep -E "Access-Control|< HTTP"

# Verify server_tokens off (should show "nginx" without version)
curl -I https://example.com | grep Server
```

---

## FinOps: Security Headers as Cost Avoidance

A successful XSS attack can result in session token theft at scale, requiring emergency incident response, customer notification, and potentially regulatory fines (GDPR Article 83 fines can reach €20M or 4% of global annual revenue). Implementing a strong CSP costs 2 hours of configuration time. The risk-adjusted cost of not implementing it is orders of magnitude higher.

NAXSI/ModSecurity running in NGINX filters malicious requests before they reach your backend application servers, reducing wasted compute on attack traffic. For a public-facing API receiving 500,000 malicious bot requests/day, WAF filtering at the NGINX layer saves approximately 10-20% of backend CPU — eliminating one application server instance.

---

## Troubleshooting

**Legitimate API calls blocked by NAXSI**

Check error.log for the blocked rule ID:
```bash
grep "NAXSI_FMT" /var/log/nginx/error.log | tail -20
```
The log shows which rule matched. Add a whitelist for that specific route and rule:
```nginx
location /api/search {
    BasicRule wl:1010 "mz:ARGS";  # Whitelist rule 1010 for query parameters
}
```

**CORS preflight works but actual request fails**

The `add_header` directives inside the `if ($request_method = OPTIONS)` block only apply to the preflight. The actual request goes through the main location block, which needs its own `add_header Access-Control-Allow-Origin`. Ensure headers are present outside the `if` block.

**CSP blocking legitimate scripts**

Enable CSP in report-only mode first to identify violations without breaking the site:
```nginx
add_header Content-Security-Policy-Report-Only "default-src 'self'; report-uri /csp-report";
```
Collect violations, add legitimate sources to the policy, then switch to enforcing mode.
