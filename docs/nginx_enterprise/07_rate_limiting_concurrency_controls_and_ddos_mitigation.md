# Module 07: Rate Limiting, Concurrency Controls & DDoS Mitigation

**Track:** Enterprise NGINX  
**Category:** Traffic Control & Attack Mitigation

---

## The Problem Rate Limiting Solves

Without rate limiting, a single client — whether a malfunctioning mobile app retrying aggressively, a scraper, or an attacker — can issue thousands of requests per second, consuming all your backend capacity and degrading service for everyone else. NGINX rate limiting enforces a maximum request rate per client before requests reach your backend.

NGINX implements rate limiting using the **leaky bucket algorithm**: requests fill a virtual bucket at whatever rate they arrive. The bucket drains at a fixed rate (your configured limit). When the bucket overflows, NGINX either queues the excess or rejects it immediately with a 429 status.

---

## The `limit_req_zone` and `limit_req` Directives

Rate limiting requires two parts: defining the zone in `http {}`, then applying it in `location {}`.

```nginx
http {
    # Define a shared memory zone to track request rates
    # Key: $binary_remote_addr — the client IP in compact 4-byte binary form
    #      (more memory-efficient than $remote_addr which stores the string)
    # zone=api_limit:10m — name "api_limit", 10MB of memory
    #      10MB stores about 160,000 IPv4 addresses simultaneously
    # rate=10r/s — allow 10 requests per second per IP address
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

    # A second zone for login endpoints — tighter limit
    limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;

    # Zone keyed by API key from header, not IP
    # Allows fair limiting per authenticated client, not per NAT exit point
    limit_req_zone $http_x_api_key zone=apikey_limit:20m rate=100r/s;
}

server {
    listen 443 ssl;
    server_name api.example.com;

    location /api/ {
        # Apply the rate limit
        # burst=20 — allow up to 20 excess requests to be queued
        #            before returning 429
        # nodelay — process queued burst requests immediately rather than
        #           spreading them out over time (reduces latency for burst)
        limit_req zone=api_limit burst=20 nodelay;

        proxy_pass http://backend;
    }

    location /auth/login {
        # Login: 5 attempts per minute, no burst queue
        limit_req zone=login_limit burst=2;

        # Return 429 Too Many Requests (not the default 503)
        limit_req_status 429;

        proxy_pass http://auth_backend;
    }
}
```

---

## Understanding `burst` and `nodelay`

The **leaky bucket** allows the rate to smooth out, but in practice APIs receive traffic in bursts. A mobile app might send 5 requests nearly simultaneously when the user opens a screen.

Without `burst`: all excess requests beyond the rate are immediately rejected.

With `burst=20`: up to 20 excess requests are queued and processed in order. If 25 requests arrive simultaneously at 10r/s, 10 are processed immediately, 20 are queued, and 5 are rejected with 429.

With `nodelay`: queued burst requests are forwarded immediately rather than being drip-fed at the configured rate. This means a burst of 30 requests (within the burst allowance) all go to the backend quickly, but the tokens are consumed. A second burst within the refill window gets rejected.

```
Without nodelay:           With nodelay:
Req 1  → processed         Req 1  → processed immediately
Req 2  → queued (100ms)    Req 2  → processed immediately
Req 3  → queued (200ms)    Req 3  → processed immediately
...                         ...
Req 11 → 429               Req 11 → 429
```

Use `nodelay` for interactive APIs. Use without it for background jobs where smoothing is acceptable.

---

## Connection Limiting with `limit_conn`

`limit_req` limits request **rate**. `limit_conn` limits **simultaneous connections** from a single client — useful for preventing a single IP from opening hundreds of keepalive connections.

```nginx
http {
    # Track simultaneous connections per IP
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
}

server {
    location /api/ {
        # Maximum 20 simultaneous connections from one IP
        limit_conn conn_limit 20;

        # Apply both connection and rate limits together
        limit_req zone=api_limit burst=20 nodelay;

        proxy_pass http://backend;
    }
}
```

---

## Blocking Bad Actors by IP, User-Agent, and Referrer

```nginx
# Block specific IP addresses or ranges
geo $blocked_ip {
    default 0;
    10.0.0.50     1;        # Single IP
    192.168.1.0/24 1;       # Entire subnet
    2001:db8::/32  1;       # IPv6 range
}

# Block by User-Agent string
map $http_user_agent $blocked_agent {
    default         0;
    "~*scrapy"      1;
    "~*python-requests" 1;
    "~*curl"        0;      # Allow curl (for your own health checks)
}

server {
    if ($blocked_ip)    { return 444; }   # 444: close connection silently
    if ($blocked_agent) { return 403; }

    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;
        proxy_pass http://backend;
    }
}
```

Return code 444 (NGINX-specific) closes the TCP connection without sending any response, conserving bandwidth against scanners.

---

## DDoS Mitigation Layers in NGINX

NGINX cannot replace a true DDoS mitigation service (Cloudflare, AWS Shield) for volumetric attacks that saturate your network interface. What NGINX can do is defend against **application-layer (Layer 7) attacks** — floods of semantically valid HTTP requests.

```nginx
http {
    # 1. Rate limit per IP
    limit_req_zone $binary_remote_addr zone=per_ip:20m rate=30r/s;

    # 2. Global rate limit across all clients combined
    limit_req_zone $server_name zone=per_server:5m rate=10000r/s;

    # 3. Limit request body size — prevents slow POST body attacks
    client_max_body_size 1m;

    # 4. Client header and body read timeouts — closes slow-read connections
    client_header_timeout 10s;
    client_body_timeout   15s;

    # 5. Close connections where the client reads the response slowly
    send_timeout 10s;

    server {
        # Apply both rate limits
        limit_req zone=per_ip     burst=50  nodelay;
        limit_req zone=per_server burst=500 nodelay;

        location / {
            proxy_pass http://backend;
        }

        # Return 444 (no response) for suspicious URIs
        location ~* \.(php|asp|aspx|jsp)$ {
            return 444;
        }

        # Block common scanner paths immediately
        location ~* /(wp-admin|phpmyadmin|\.env|\.git) {
            return 444;
        }
    }
}
```

---

## GeoIP-Based Rate Limiting and Blocking

With `ngx_http_geoip_module` and MaxMind GeoIP2 databases:

```nginx
http {
    geoip2 /etc/nginx/GeoLite2-Country.mmdb {
        $geoip_country_code default=XX source=$remote_addr country iso_code;
    }

    map $geoip_country_code $allowed_country {
        default 0;
        US      1;
        CA      1;
        GB      1;
        DE      1;
    }
}

server {
    location /api/ {
        if ($allowed_country = 0) {
            return 403 "Access restricted to supported regions.";
        }
        proxy_pass http://backend;
    }
}
```

---

## CLI: Monitoring Rate Limit Events

```bash
# Count rate limit rejections (503 or 429) in real time
tail -f /var/log/nginx/access.log \
    | awk '$9 == "429" || $9 == "503" {print $1, $9}'

# Find top IP addresses being rate limited
grep " 429 " /var/log/nginx/access.log \
    | awk '{print $1}' \
    | sort | uniq -c | sort -rn | head -20

# Watch error log for limit_req events
tail -f /var/log/nginx/error.log \
    | grep "limiting requests"

# Current connection counts per remote IP (from NGINX status)
curl -s http://127.0.0.1:8080/nginx_status
```

---

## FinOps: Rate Limiting Reduces Backend Over-Provisioning

Without rate limiting, backend capacity must be sized for worst-case client misbehavior — a single script can trigger the need to scale out. With per-IP limits of 30r/s, a single client generating 10,000 req/s contributes only 30r/s to backend load. This means backend capacity can be sized for legitimate peak traffic only, reducing over-provisioning costs.

For a Node.js API cluster on AWS, rate limiting at NGINX often allows running 3 backend instances during normal traffic instead of 8 instances sized for abuse scenarios — saving approximately $800/month on `t3.large` instances.

---

## Troubleshooting Rate Limiting

**Legitimate users getting 429 errors**

Your `rate` is too strict or your `burst` is too small for the actual usage pattern. Check what your legitimate clients actually do:

```bash
# Find max burst per IP in a 1-second window
awk '{print $4, $1}' /var/log/nginx/access.log \
    | awk '{gsub(/\[/,"",$1); print $1, $2}' \
    | sort | uniq -c | sort -rn | head -30
```

Set `burst` to cover your 99th percentile legitimate burst size.

**Rate limiting not working — attackers still getting through**

If the attacker is using many different IP addresses (a botnet), per-IP rate limiting is insufficient. Add a global `per_server` zone as shown above, or use Cloudflare or AWS WAF to apply challenge pages and IP reputation filtering upstream.

**`limit_req_zone` running out of memory**

NGINX logs: `ngx_http_limit_req_module: zone "api_limit" ran out of memory`. Increase the zone size or reduce the `inactive` timeout for entries:

```nginx
# 10m holds ~160,000 IPs. 50m holds ~800,000 IPs.
limit_req_zone $binary_remote_addr zone=api_limit:50m rate=10r/s;
```
