# Module 04: Load Balancing Algorithms, Health Checks & Session Persistence

**Track:** Enterprise NGINX  
**Category:** Traffic Distribution & Backend Reliability

---

## What Is Load Balancing?

When your application needs to handle more traffic than a single server can process, you run multiple identical server instances and use NGINX to spread incoming requests across them. This is **load balancing**. NGINX decides which backend server gets each request based on an **algorithm** you configure.

The goals are threefold: distribute work evenly, detect and avoid unhealthy servers automatically, and when required, route the same user to the same server consistently.

---

## The Five Built-In Load Balancing Algorithms

### 1. Round Robin (default)

The simplest algorithm. Requests rotate through the server list in order: first request → server A, second → server B, third → server C, fourth → server A again.

```nginx
upstream api_servers {
    server 10.0.0.1:3000;
    server 10.0.0.2:3000;
    server 10.0.0.3:3000;
    # No directive needed — round robin is the default
}
```

Works well when: all servers have identical hardware and your requests take similar time to process.

Fails when: some servers are slower or some requests are much heavier than others.

### 2. Weighted Round Robin

Assigns proportional traffic share. A server with `weight=3` receives three times as many requests as a server with `weight=1`. Use this when servers have different CPU/RAM.

```nginx
upstream api_servers {
    server 10.0.0.1:3000 weight=5;   # c5.2xlarge — 8 vCPU
    server 10.0.0.2:3000 weight=3;   # c5.xlarge  — 4 vCPU
    server 10.0.0.3:3000 weight=2;   # t3.large   — 2 vCPU
    # Traffic split: 50% / 30% / 20%
}
```

### 3. Least Connections (`least_conn`)

Sends each new request to whichever server currently has the fewest active connections. Automatically compensates for long-running requests piling up on one server.

```nginx
upstream api_servers {
    least_conn;
    server 10.0.0.1:3000;
    server 10.0.0.2:3000;
    server 10.0.0.3:3000;
}
```

Use this for: API gateways, database proxy tiers, or any workload where request processing time varies significantly.

### 4. IP Hash

Generates a hash from the client's IP address and always routes that IP to the same backend server. This provides rudimentary session affinity without cookies.

```nginx
upstream api_servers {
    ip_hash;
    server 10.0.0.1:3000;
    server 10.0.0.2:3000;
    server 10.0.0.3:3000;
}
```

Limitation: if a client is behind a corporate NAT, all employees share one IP and land on the same server. Use cookie-based persistence instead (NGINX Plus or via Lua).

### 5. Hash (Generic, with `consistent` option)

Hash any NGINX variable — request URI, custom header, cookie value. The `consistent` option uses a **consistent hash ring** so that adding or removing a server only remaps a fraction of keys (versus remapping everything on a standard hash).

```nginx
upstream cache_servers {
    hash $request_uri consistent;
    server 10.0.0.1:6379;
    server 10.0.0.2:6379;
    server 10.0.0.3:6379;
}
```

This is how distributed caches are sharded: the same URL always hits the same cache node, maximizing hit rates.

---

## Server Parameters: weight, max_fails, fail_timeout, backup, down

```nginx
upstream api_servers {
    server 10.0.0.1:3000 weight=3 max_fails=3 fail_timeout=30s;
    server 10.0.0.2:3000 weight=3 max_fails=3 fail_timeout=30s;
    server 10.0.0.3:3000 weight=1 max_fails=3 fail_timeout=30s;

    # Only used when all primary servers are down
    server 10.0.0.4:3000 backup;

    # Permanently excluded from rotation (for maintenance)
    server 10.0.0.5:3000 down;
}
```

| Parameter | Meaning |
|---|---|
| `weight=N` | Relative traffic share (default: 1) |
| `max_fails=N` | Failed connections before server is marked unavailable |
| `fail_timeout=Xs` | How long a failed server stays out of rotation |
| `backup` | Only receives traffic when all non-backup servers fail |
| `down` | Permanently excluded; useful during rolling deploys |

**How passive health checking works:** NGINX marks a server as failed after `max_fails` consecutive connection errors or non-2xx responses within a `fail_timeout` window. After `fail_timeout` seconds, it tries the server again with one probe request.

---

## Active Health Checks (NGINX Open Source via `nginx_upstream_check_module`)

The standard NGINX open-source build performs only **passive** health checks (it discovers failures from real traffic). For **active** polling of backend `/health` endpoints, you need the third-party `nginx_upstream_check_module` or NGINX Plus.

With `nginx_upstream_check_module` compiled in:

```nginx
upstream api_servers {
    server 10.0.0.1:3000;
    server 10.0.0.2:3000;
    server 10.0.0.3:3000;

    check interval=3000 rise=2 fall=3 timeout=1000 type=http;
    check_http_send "GET /health HTTP/1.0\r\nHost: api\r\n\r\n";
    check_http_expect_alive http_2xx http_3xx;
}
```

| Parameter | Meaning |
|---|---|
| `interval=3000` | Poll every 3 seconds |
| `rise=2` | Mark healthy after 2 consecutive successes |
| `fall=3` | Mark unhealthy after 3 consecutive failures |
| `timeout=1000` | Health check connection timeout in milliseconds |

---

## Session Persistence with a Sticky Cookie

When your application stores session state in server memory (instead of Redis), every request from the same user must land on the same backend. The cleanest approach is setting a **sticky cookie** that encodes which server to use.

NGINX open source does not have native sticky cookies. The simplest solution without NGINX Plus is to route based on an existing application-set cookie:

```nginx
upstream api_servers {
    hash $cookie_session_id consistent;
    server 10.0.0.1:3000;
    server 10.0.0.2:3000;
    server 10.0.0.3:3000;
}

server {
    listen 443 ssl;
    location /api/ {
        proxy_pass http://api_servers;
        proxy_set_header Host $host;
    }
}
```

This hashes the value of the `session_id` cookie and consistently routes to the same server. When a server is removed, only sessions that were pinned to it get disrupted.

---

## Complete Production Load Balancer Configuration

```nginx
# /etc/nginx/conf.d/production-lb.conf

upstream web_app {
    least_conn;

    server 10.0.0.1:8080 weight=2 max_fails=2 fail_timeout=20s;
    server 10.0.0.2:8080 weight=2 max_fails=2 fail_timeout=20s;
    server 10.0.0.3:8080 weight=1 max_fails=2 fail_timeout=20s;
    server 10.0.0.4:8080 backup;

    keepalive 64;
    keepalive_timeout 60s;
    keepalive_requests 2000;
}

server {
    listen 443 ssl http2;
    server_name app.example.com;

    ssl_certificate     /etc/ssl/certs/app.crt;
    ssl_certificate_key /etc/ssl/private/app.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        proxy_pass         http://web_app;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        proxy_connect_timeout 3s;
        proxy_read_timeout    30s;
        proxy_send_timeout    10s;

        # Retry on failure, but not on POST (would duplicate mutations)
        proxy_next_upstream error timeout http_502 http_503;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 5s;
    }

    # Real-time upstream state dashboard
    location /upstream_status {
        check_status;
        access_log off;
        allow 10.0.0.0/8;
        deny  all;
    }
}
```

---

## CLI Reference

```bash
# Test upstream connectivity from NGINX host
curl -v http://10.0.0.1:8080/health

# Watch live connection distribution across backends
watch -n 1 'ss -tn | grep :8080 | awk "{print \$5}" | sort | uniq -c'

# Reload NGINX after upstream changes (zero downtime)
nginx -t && nginx -s reload

# Temporarily remove a server for maintenance by marking it down
# Edit nginx.conf, set server ... down;
nginx -s reload

# Confirm round-robin weight distribution from access log
awk '{print $8}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -5
```

---

## FinOps: Load Balancer Cost Optimization

Running 3 application servers behind NGINX on EC2 instead of using an AWS Application Load Balancer (ALB) saves approximately $16-22/month per ALB. For a deployment with 10 environments (dev, staging, prod × 3 regions), eliminating managed load balancers saves around $200/month, while also removing per-LCU pricing that appears during traffic spikes.

Configuring `keepalive 64` on the upstream pool eliminates the TCP handshake cost for every proxied request. At 5,000 req/sec, this reduces backend CPU utilization by 12-18%, allowing you to downsize backend instances by one tier (e.g., c5.xlarge → c5.large, saving $73/month per instance).

---

## Troubleshooting

**Problem: 502 errors during deployment when rolling a backend**

Root cause: NGINX probes the new instance before it finishes starting. The `max_fails=1 fail_timeout=5s` defaults are too aggressive for slow-starting JVM or Python applications.

Fix: Give the application more time and more tolerance before marking it failed.
```nginx
server 10.0.0.1:8080 max_fails=5 fail_timeout=60s;
```
Also use `proxy_next_upstream error timeout http_502 http_503;` so failing requests retry on a different server automatically.

**Problem: One backend receives far more connections than others under `least_conn`**

Root cause: That server has faster responses, so its connection count stays lower, attracting more new requests in a feedback loop.

Fix: Switch to weighted round robin. `least_conn` works best when request durations are uniformly distributed.

**Problem: Session data lost when a backend fails**

Root cause: IP hash or cookie hash was routing a user to a server that is now down. NGINX has no choice but to send that user to a different server which has no session data.

Fix: Move session storage out of server memory into a shared store (Redis with `ioredis`, PostgreSQL sessions). Then session persistence directives become irrelevant — any server can serve any user.
