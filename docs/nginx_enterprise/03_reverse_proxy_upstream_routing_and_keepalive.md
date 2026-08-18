# Module 03: Reverse Proxy, Upstream Routing & Keepalive Connection Pools

**Track:** Enterprise NGINX  
**Category:** Reverse Proxy Architecture & Upstream Connection Management  
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. What Is a Reverse Proxy?

A **reverse proxy** sits in front of application servers and forwards client requests to them. From the client's perspective, they are talking directly to NGINX — they never see the backend servers. This is different from a **forward proxy** (which represents clients, like a corporate internet gateway).

```
WITHOUT Reverse Proxy:
  Client ──────────────────────────> Node.js :3000
  Client ──────────────────────────> Node.js :3001  (different servers!)

WITH NGINX Reverse Proxy:
  Client ──> NGINX :443 ──> Node.js :3000  (client sees only NGINX)
                       ──> Node.js :3001  (load balanced)
                       ──> Node.js :3002
```

**Why use a reverse proxy?**
- **TLS termination**: NGINX handles encryption; backends use plain HTTP
- **Load balancing**: Distribute requests across multiple backend instances
- **Caching**: Cache backend responses, reducing backend load
- **Security**: Backend servers are not exposed to the internet
- **HTTP/2 to HTTP/1.1 translation**: Clients use HTTP/2; backends use HTTP/1.1
- **Connection pooling**: Reuse TCP connections to backends (keepalive)

---

## 2. Basic Reverse Proxy Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    # ─────────────────────────────────────────
    # BASIC PROXY DIRECTIVES
    # ─────────────────────────────────────────

    location /api/ {
        # Forward to backend (URL with or without trailing slash matters!)
        # proxy_pass http://backend:3000;  → passes /api/users AS /api/users
        # proxy_pass http://backend:3000/; → strips /api/ prefix, passes /users
        proxy_pass http://backend:3000;

        # ─────────────────────────────────────
        # REQUIRED HEADERS FOR CORRECT BEHAVIOR
        # ─────────────────────────────────────

        # Preserve the original Host header (backend needs this for routing)
        proxy_set_header Host $host;

        # Tell backend the real client IP
        proxy_set_header X-Real-IP $remote_addr;

        # Append to the forwarded-for chain (supports existing proxies)
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # Tell backend whether original request was HTTP or HTTPS
        proxy_set_header X-Forwarded-Proto $scheme;

        # ─────────────────────────────────────
        # TIMEOUTS
        # ─────────────────────────────────────

        # Time to establish TCP connection to backend
        proxy_connect_timeout 5s;

        # Time to receive first byte of response from backend
        proxy_read_timeout 60s;

        # Time to send request data to backend
        proxy_send_timeout 30s;

        # ─────────────────────────────────────
        # BUFFERING
        # ─────────────────────────────────────

        # Buffer backend responses in memory before sending to client
        proxy_buffering on;

        # Size of buffer for reading the first part of response
        proxy_buffer_size 4k;

        # Buffers for the rest of the response
        proxy_buffers 8 4k;
    }
}
```

---

## 3. The `upstream` Block — Backend Pools

The `upstream` block defines a named pool of backend servers that NGINX can proxy to:

```nginx
http {
    # Define backend server pool
    upstream node_app {
        # Backend server instances
        server 10.0.0.1:3000;
        server 10.0.0.2:3000;
        server 10.0.0.3:3000;

        # Keepalive connections to backends (critical for performance!)
        # Keeps this many idle connections open per worker
        keepalive 32;

        # Timeout for idle keepalive connections
        keepalive_timeout 60s;

        # Max requests on a single keepalive connection
        keepalive_requests 1000;
    }

    server {
        listen 443 ssl http2;

        location /api/ {
            proxy_pass http://node_app;

            # Required for keepalive connections to work!
            proxy_http_version 1.1;
            proxy_set_header Connection "";

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
```

### Why Keepalive Is Critical for Performance

**Without keepalive** (every request):
```
Client → NGINX → [TCP SYN] → Backend
                ← [SYN-ACK]
                → [ACK]
                → [HTTP request]
                ← [HTTP response]
                → [FIN]
Total: 3 extra round trips per request!
```

**With keepalive** (after first connection):
```
Client → NGINX → [existing TCP connection]
                → [HTTP request]
                ← [HTTP response]
Total: 0 extra round trips!
```

At 1,000 RPS with 1ms round-trip latency to the backend:
- Without keepalive: 3,000ms wasted on handshakes/second
- With keepalive: ~0ms overhead

---

## 4. Proxy Rewrite & URL Stripping

A common pattern is stripping the path prefix before forwarding:

```nginx
# Pattern 1: Strip /api prefix before forwarding
# Request: GET /api/users → Backend receives: GET /users
location /api/ {
    proxy_pass http://backend:3000/;  # Trailing slash strips prefix
}

# Pattern 2: Keep the /api prefix
# Request: GET /api/users → Backend receives: GET /api/users
location /api/ {
    proxy_pass http://backend:3000;   # No trailing slash keeps prefix
}

# Pattern 3: Rewrite before proxying
location /legacy/ {
    rewrite ^/legacy/(.*)$ /v2/$1 break;
    proxy_pass http://backend:3000;
}

# Pattern 4: Proxy to a subpath on backend
# Request: GET /data → Backend receives: GET /internal/v1/data
location /data {
    proxy_pass http://backend:3000/internal/v1/data;
}
```

---

## 5. Passing Headers to Backend Applications

A production-ready proxy headers snippet:

```nginx
# /etc/nginx/snippets/proxy-headers.conf
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $server_name;
proxy_set_header X-Request-Id $request_id;  # Unique ID per request (NGINX Plus)
```

```nginx
server {
    location /api/ {
        include /etc/nginx/snippets/proxy-headers.conf;
        proxy_pass http://node_app;
    }
}
```

---

## 6. WebSocket Proxying

WebSocket connections require a special upgrade handshake:

```nginx
# Map to handle WebSocket upgrade header properly
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    location /ws/ {
        proxy_pass http://websocket_backend;

        # WebSocket upgrade headers
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Keep WebSocket connections alive (long timeout)
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 7. Production Proxy Configuration (Complete Example)

```nginx
# /etc/nginx/conf.d/production-api.conf

upstream api_backend {
    server 10.0.0.1:8080 weight=3;    # Receives 3x more traffic
    server 10.0.0.2:8080 weight=2;
    server 10.0.0.3:8080 weight=1;
    server 10.0.0.4:8080 backup;      # Only used when others are down

    keepalive 64;
    keepalive_timeout 75s;
    keepalive_requests 2000;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/ssl/api.example.com.fullchain.pem;
    ssl_certificate_key /etc/ssl/api.example.com.privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Request size limit
    client_max_body_size 10m;
    client_body_timeout 30s;

    # Response caching (next module covers this in depth)
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m;

    location /api/ {
        # Include standard proxy headers
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Backend timeout configuration
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;

        # Retry on backend failure
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 10s;

        # Pass to upstream pool
        proxy_pass http://api_backend;

        # Cache successful GET responses for 60 seconds
        proxy_cache api_cache;
        proxy_cache_valid 200 60s;
        proxy_cache_methods GET HEAD;
        proxy_cache_use_stale error timeout updating;
        add_header X-Cache-Status $upstream_cache_status;
    }

    # Health check endpoint (not cached)
    location /health {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_cache off;
    }

    # WebSocket endpoint
    location /ws/ {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_set_header Host $host;
    }
}
```

---

## 8. CLI Commands for Proxy Troubleshooting

```bash
# ─────────────────────────────────────────────
# TESTING PROXY BEHAVIOR
# ─────────────────────────────────────────────

# Test proxy with custom headers
curl -v \
    -H "Host: api.example.com" \
    https://api.example.com/api/users

# Check what headers backend actually receives
curl https://api.example.com/api/echo-headers

# Test WebSocket connectivity
curl \
    --include \
    --no-buffer \
    --header "Connection: Upgrade" \
    --header "Upgrade: websocket" \
    --header "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
    --header "Sec-WebSocket-Version: 13" \
    http://api.example.com/ws/

# ─────────────────────────────────────────────
# MONITORING UPSTREAM HEALTH
# ─────────────────────────────────────────────

# View NGINX upstream status (requires ngx_http_upstream_module)
curl http://127.0.0.1:8080/upstream_status

# Real-time connection tracking
watch -n 1 'ss -s | grep -E "estab|ESTAB"'

# Count connections per upstream backend
ss -tn dst 10.0.0.1:8080 | wc -l

# ─────────────────────────────────────────────
# ERROR LOG MONITORING
# ─────────────────────────────────────────────

# Monitor proxy errors in real time
sudo tail -f /var/log/nginx/error.log | grep -E "upstream|connect"

# Count upstream connection failures
grep "connect() failed" /var/log/nginx/error.log | wc -l
```

---

## 9. FinOps & Cloud Resource Cost Governance

### Keepalive Connections Reduce Backend Server Count
Without keepalive, an NGINX proxy to a Node.js backend requires Node.js to handle 3 TCP operations per request. At 5,000 RPS with 20 backend instances, enabling `keepalive 64` reduces backend CPU overhead from TLS/TCP handshakes by ~20%, allowing removal of 4 backend instances (saving $400-$800/month on t3.medium instances).

### `proxy_next_upstream` Eliminates Client-Visible Failures
Automatically retrying failed upstream requests transparently prevents error responses to clients during rolling deployments, eliminating the need for external health check systems that cost $50-$200/month in managed services.

---

## 10. Troubleshooting Reverse Proxy Issues

### Issue: 502 Bad Gateway
**Cause**: NGINX cannot reach the backend server.
**Diagnosis**:
```bash
# Check if backend is running
curl http://10.0.0.1:3000/health

# Check NGINX error log
tail -100 /var/log/nginx/error.log | grep "connect() failed"

# Test network connectivity
nc -zv 10.0.0.1 3000
```

### Issue: Requests Hang (504 Gateway Timeout)
**Cause**: Backend is processing too slowly; `proxy_read_timeout` expires.
**Diagnosis**: Monitor backend response times:
```bash
tail -f /var/log/nginx/access.log | awk '{print $NF}'  # Print request_time
```
**Fix**: Increase timeout for slow endpoints:
```nginx
location /api/slow-report {
    proxy_read_timeout 300s;  # 5 minutes for heavy reports
    proxy_pass http://api_backend;
}
```

### Issue: Missing Real Client IP in Backend Logs
**Cause**: Backend reads `REMOTE_ADDR` (NGINX's IP) instead of `X-Real-IP`.
**Fix**: Configure backend to trust proxy headers:
- Express.js: `app.set('trust proxy', 1)`
- Fastify: `app.register(fastify-ip)` or configure `trustProxy`

---

## References

### Official Documentation
* [NGINX Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) — Official reverse proxy tutorial.
* [NGINX `proxy_pass` Directive](https://nginx.org/en/docs/http/ngx_http_proxy_module.html) — Complete proxy module reference.
* [NGINX Upstream Module](https://nginx.org/en/docs/http/ngx_http_upstream_module.html) — upstream block directive reference.
* [NGINX WebSocket Proxying](https://nginx.org/en/docs/http/websocket.html) — Official WebSocket guide.
* [NGINX `proxy_next_upstream`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_next_upstream) — Failover configuration.

### Authoritative Engineering Blogs
* [NGINX Blog: NGINX as a WebSocket Proxy](https://www.nginx.com/blog/websocket-nginx/) — Official WebSocket proxying guide.
* [Dropbox Engineering: Making Backend Applications Faster](https://dropbox.tech/) — Keepalive connection pool optimization at scale.
* [Netflix TechBlog: NGINX at Netflix](https://netflixtechblog.com/) — Reverse proxy at internet scale.
* [Envoy Proxy vs NGINX: A Performance Comparison](https://www.envoyproxy.io/) — Understanding proxy architectures.
* [Brendan Gregg: HTTP Latency Profiling](https://www.brendangregg.com/blog/2014-09-17/node-flame-graphs-on-linux.html) — Profiling reverse proxy bottlenecks.
