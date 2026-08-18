# Module 13: Real-World Production Case Studies & Enterprise Blueprints

**Track:** Enterprise NGINX  
**Category:** Production Architecture & Applied Patterns

---

## Overview

This module assembles everything from the preceding modules into complete, deployable production architectures. Each case study reflects a real category of production deployment: an e-commerce edge, a microservices API gateway, a global CDN origin shield, and a WebSocket-heavy real-time platform. Every configuration is annotated to explain the reasoning behind each directive.

---

## Case Study 1: E-Commerce Edge Server

An e-commerce platform with 2 million daily users. The stack: React SPA served as static files, a Node.js API backend, and a PostgreSQL database proxied through NGINX's stream module.

**Requirements:**
- Static assets: CDN-cached for 1 year with hashed filenames (Vite build output)
- Product catalog API: cached at NGINX for 5 minutes
- Checkout API: never cached, full authentication required
- DDoS protection: rate limiting per IP
- TLS with HTTP/2, OCSP stapling

```nginx
# /etc/nginx/nginx.conf
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 16384;
    multi_accept on;
}

http {
    include      mime.types;
    default_type application/octet-stream;

    sendfile    on;
    tcp_nopush  on;
    tcp_nodelay on;

    keepalive_timeout  65;
    keepalive_requests 10000;

    # JSON structured logging
    log_format json escape=json
        '{"t":"$time_iso8601","ip":"$remote_addr","method":"$request_method",'
        '"uri":"$uri","status":$status,"rt":"$request_time",'
        '"urt":"$upstream_response_time","cache":"$upstream_cache_status"}';

    # Static assets cache (CDN should be in front, this is origin shield)
    proxy_cache_path /var/cache/nginx/catalog
        levels=1:2 keys_zone=catalog:20m max_size=4g inactive=1d use_temp_path=off;

    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=per_ip:20m rate=50r/s;
    limit_req_zone $binary_remote_addr zone=checkout:10m rate=5r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=3r/m;

    # Upstream: Node.js API cluster
    upstream api_cluster {
        least_conn;
        server 10.0.0.1:3000 weight=3 max_fails=2 fail_timeout=15s;
        server 10.0.0.2:3000 weight=3 max_fails=2 fail_timeout=15s;
        server 10.0.0.3:3000 weight=2 max_fails=2 fail_timeout=15s;
        server 10.0.0.4:3000 backup;
        keepalive 64;
        keepalive_timeout 60s;
        keepalive_requests 2000;
    }

    include /etc/nginx/conf.d/*.conf;
}

stream {
    upstream postgres {
        server 10.0.0.10:5432 max_fails=3 fail_timeout=30s;
        server 10.0.0.11:5432 backup;
    }
    server {
        listen 5432;
        allow 10.0.0.0/8;
        deny  all;
        proxy_pass postgres;
        proxy_timeout 30m;
        proxy_connect_timeout 5s;
        proxy_socket_keepalive on;
    }
}
```

```nginx
# /etc/nginx/conf.d/ecommerce.conf

server {
    listen 80;
    server_name shop.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name shop.example.com;

    root /var/www/shop/dist;

    ssl_certificate     /etc/ssl/shop.example.com.fullchain.pem;
    ssl_certificate_key /etc/ssl/shop.example.com.privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_stapling        on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/ssl/shop.example.com.chain.pem;
    resolver            8.8.8.8 valid=300s;

    server_tokens off;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # -- Static SPA files (Vite build with content-hashed filenames) ---------
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable" always;
        add_header Vary "Accept-Encoding" always;
        gzip_static on;
        access_log off;
    }

    # -- SPA routing: serve index.html for all frontend routes ---------------
    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-store" always;
    }

    # -- Product catalog API: cacheable --------------------------------------
    location /api/v1/products {
        limit_req zone=per_ip burst=30 nodelay;

        proxy_cache       catalog;
        proxy_cache_valid 200 5m;
        proxy_cache_key   "$scheme$host$request_uri";
        proxy_cache_use_stale error timeout updating;
        proxy_cache_lock  on;
        add_header        X-Cache-Status $upstream_cache_status always;

        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        proxy_connect_timeout 3s;
        proxy_read_timeout    15s;
        proxy_next_upstream   error timeout http_502 http_503;

        proxy_pass http://api_cluster;
    }

    # -- Checkout: never cache, tighter rate limit ---------------------------
    location /api/v1/checkout {
        limit_req zone=checkout burst=5 nodelay;

        proxy_no_cache    1;
        proxy_cache_bypass 1;

        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        proxy_connect_timeout 5s;
        proxy_read_timeout    30s;

        proxy_pass http://api_cluster;
    }

    # -- Auth endpoints: strictest rate limit --------------------------------
    location /api/v1/auth {
        limit_req zone=login burst=2;
        limit_req_status 429;

        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_set_header   Host              $host;
        proxy_set_header   X-Forwarded-Proto $scheme;

        proxy_pass http://api_cluster;
    }

    access_log /var/log/nginx/shop.access.json json;
    error_log  /var/log/nginx/shop.error.log warn;
}
```

---

## Case Study 2: Microservices API Gateway

A B2B SaaS platform with 12 microservices. Each service owns its domain: users, billing, notifications, reports, etc. NGINX acts as the API gateway with JWT authentication via `auth_request`.

```nginx
# /etc/nginx/conf.d/api-gateway.conf

# All upstream microservices (internal Kubernetes services in this example)
upstream svc_users        { server users-svc:8080;        keepalive 32; }
upstream svc_billing      { server billing-svc:8080;      keepalive 32; }
upstream svc_notifications { server notifications-svc:8080; keepalive 16; }
upstream svc_reports      { server reports-svc:8080;      keepalive 16; }
upstream svc_auth         { server auth-svc:8080;         keepalive 64; }

# Rate limiting per API key
limit_req_zone $http_x_api_key zone=by_key:20m rate=200r/s;

server {
    listen 443 ssl;
    http2 on;
    server_name api.saas.example.com;

    ssl_certificate     /etc/ssl/api.saas.example.com.fullchain.pem;
    ssl_certificate_key /etc/ssl/api.saas.example.com.privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:APISSL:20m;

    server_tokens off;
    client_max_body_size 50m;

    # Auth subrequest internal endpoint
    location /internal/auth {
        internal;
        proxy_pass              http://svc_auth/validate;
        proxy_pass_request_body off;
        proxy_set_header        Content-Length "";
        proxy_set_header        X-Original-URI $request_uri;
        proxy_set_header        Authorization $http_authorization;
        proxy_connect_timeout   2s;
        proxy_read_timeout      5s;
    }

    # ── Route: User management ──────────────────────────────────────────────
    location /v1/users {
        auth_request /internal/auth;
        auth_request_set $user_id   $upstream_http_x_user_id;
        auth_request_set $user_role $upstream_http_x_user_role;
        error_page 401 = @auth_error;

        limit_req zone=by_key burst=50 nodelay;

        proxy_set_header X-User-Id   $user_id;
        proxy_set_header X-User-Role $user_role;
        proxy_set_header Host        $host;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";

        proxy_pass http://svc_users;
    }

    # ── Route: Billing (admin only enforced at service level) ───────────────
    location /v1/billing {
        auth_request /internal/auth;
        auth_request_set $user_id   $upstream_http_x_user_id;
        auth_request_set $user_role $upstream_http_x_user_role;
        error_page 401 = @auth_error;
        error_page 403 = @forbidden_error;

        limit_req zone=by_key burst=20 nodelay;

        proxy_set_header X-User-Id   $user_id;
        proxy_set_header X-User-Role $user_role;
        proxy_set_header Host        $host;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";

        proxy_pass http://svc_billing;
    }

    # ── Route: Reports (long-running, higher timeout) ───────────────────────
    location /v1/reports {
        auth_request /internal/auth;
        auth_request_set $user_id $upstream_http_x_user_id;
        error_page 401 = @auth_error;

        limit_req zone=by_key burst=5 nodelay;

        proxy_set_header X-User-Id $user_id;
        proxy_set_header Host      $host;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_read_timeout 300s;    # Reports can take up to 5 minutes

        proxy_pass http://svc_reports;
    }

    # ── Named error handlers ────────────────────────────────────────────────
    location @auth_error {
        add_header Content-Type application/json always;
        return 401 '{"error":"unauthorized","code":"INVALID_TOKEN","message":"A valid bearer token is required."}';
    }

    location @forbidden_error {
        add_header Content-Type application/json always;
        return 403 '{"error":"forbidden","code":"INSUFFICIENT_PERMISSIONS","message":"Your role does not permit this action."}';
    }

    access_log /var/log/nginx/api-gateway.json json;
}
```

---

## Case Study 3: Real-Time WebSocket Platform

A live collaboration platform (like Figma or Google Docs). Thousands of users maintain persistent WebSocket connections. NGINX manages connection distribution and handles reconnection gracefully.

```nginx
upstream collab_servers {
    ip_hash;    # Sticky routing — same user always hits same server (session state)
    server 10.0.0.1:4000 max_fails=1 fail_timeout=5s;
    server 10.0.0.2:4000 max_fails=1 fail_timeout=5s;
    server 10.0.0.3:4000 max_fails=1 fail_timeout=5s;
}

map $http_upgrade $connection_upgrade {
    default  upgrade;
    ""       close;
}

server {
    listen 443 ssl;
    http2 on;
    server_name collab.example.com;

    ssl_certificate     /etc/ssl/collab.fullchain.pem;
    ssl_certificate_key /etc/ssl/collab.privkey.pem;
    ssl_protocols       TLSv1.3;
    ssl_session_cache   shared:WS:10m;

    # WebSocket connections stay open for hours — tune timeouts accordingly
    location /ws/ {
        proxy_pass         http://collab_servers;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection $connection_upgrade;
        proxy_set_header   Host       $host;
        proxy_set_header   X-Real-IP  $remote_addr;

        # Do not timeout long-lived idle WebSocket connections
        proxy_read_timeout  7200s;   # 2 hours
        proxy_send_timeout  7200s;
        proxy_connect_timeout 5s;

        # Disable buffering — WebSocket messages need immediate forwarding
        proxy_buffering off;
    }

    # REST API for non-realtime operations (document save, etc.)
    location /api/ {
        proxy_pass         http://collab_servers;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_set_header   Host $host;
        proxy_read_timeout 30s;
    }
}
```

---

## Deployment Checklist

Before taking any NGINX configuration to production, verify these items:

```bash
# 1. Syntax check (always — before every reload)
nginx -t

# 2. Verify TLS certificate chain is complete
openssl s_client -connect domain.com:443 -showcerts </dev/null 2>/dev/null | grep "BEGIN CERT" | wc -l

# 3. Confirm HTTP/2 is active
curl -I --http2 https://domain.com | grep "HTTP/"

# 4. Verify security headers are present
curl -I https://domain.com | grep -E "Strict-Transport|X-Frame|X-Content"

# 5. Test rate limiting is working
for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code} " https://domain.com/api/; done

# 6. Test backend failover (mark one server down, verify traffic routes to others)
# Edit upstream, set server ... down; reload; check access.log

# 7. Confirm gzip is active
curl -H "Accept-Encoding: gzip" -I https://domain.com | grep "Content-Encoding"

# 8. Verify cache is working
curl -I https://domain.com/api/products | grep "X-Cache-Status"

# 9. Load test before going live
ab -n 10000 -c 100 https://domain.com/api/products

# 10. Monitor error rate during and after deployment
tail -f /var/log/nginx/access.json | jq -r 'select(.status >= 500) | "\(.status) \(.uri)"'
```

---

## Key Configuration Anti-Patterns to Avoid

**Never use `if` for complex routing logic** — `if` in NGINX `location` blocks has non-obvious behavior. Use `map` and `try_files` instead.

**Never remove `proxy_http_version 1.1; proxy_set_header Connection "";`** when using `keepalive` in upstream. Without these, keepalive connections are never established.

**Never set `worker_processes` higher than the CPU core count** — extra workers compete for the same CPU time, increasing context switch overhead.

**Never deploy without `nginx -t`** — a syntax error in `nginx.conf` causes the reload to silently fail, leaving the old configuration running. Worse, `nginx -s reload` with a fatal error kills the master and brings down the site.

**Never log every static asset request** — enables targeted reduction in log volume and I/O pressure without losing diagnostic data for application requests.
