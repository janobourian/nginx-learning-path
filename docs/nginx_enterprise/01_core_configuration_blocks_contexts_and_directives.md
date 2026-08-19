# Module 01: Core Configuration Blocks, Contexts & Directives

**Track:** Enterprise NGINX
**Category:** Configuration Language & Directive Hierarchy
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. Understanding NGINX Configuration as a Structured Language

NGINX configuration is not a flat key-value file. It is a **hierarchical document** organized into nested blocks called **contexts**. Think of it like a tree — settings defined in a parent context apply to all children, unless overridden.

**The Golden Rule**: A directive in a **child context** takes precedence over the same directive in its **parent context**.

```text
nginx.conf
└── main context (global)
    ├── events { }           ← connection handling
    ├── http { }             ← HTTP server behavior
    │   ├── server { }       ← one virtual host
    │   │   ├── location / { }   ← URL pattern handler
    │   │   └── location /api/ { }
    │   └── server { }       ← another virtual host
    ├── stream { }           ← TCP/UDP load balancing
    └── mail { }             ← mail proxy (rare)

```

---

## 2. The Main (Global) Context

Directives in the **main context** apply to the entire NGINX process:

```nginx

# /etc/nginx/nginx.conf

# User the worker processes run as (drop root privileges)
user nginx;

# One worker per CPU core (auto = detect automatically)
worker_processes auto;

# Path to store the master process PID
pid /run/nginx.pid;

# Include modular configuration files
include /etc/nginx/modules-enabled/*.conf;

# Raise OS file descriptor limit for worker processes
worker_rlimit_nofile 65535;

# Error log: path and minimum severity level

# Levels: debug, info, notice, warn, error, crit, alert, emerg
error_log /var/log/nginx/error.log warn;

```

---

## 3. The `events` Context

Controls how NGINX handles connections at the OS level:

```nginx
events {
    # Maximum simultaneous connections per worker
    # Total capacity = worker_processes × worker_connections
    worker_connections 16384;

    # Accept multiple connections in a single epoll_wait() call
    multi_accept on;

    # Event model: epoll (Linux), kqueue (BSD/macOS), select (fallback)
    # NGINX auto-selects the best available model
    use epoll;
}

```

---

## 4. The `http` Context

The `http` block controls all HTTP/HTTPS server behavior. Directives here serve as **defaults** that apply to every `server {}` block unless overridden:

```nginx
http {
    # Include MIME type definitions (text/html, image/png, etc.)
    include       /etc/nginx/mime.types;

    # Default MIME type for unknown file extensions
    default_type  application/octet-stream;

    # ─────────────────────────────────────────────
    # PERFORMANCE DIRECTIVES
    # ─────────────────────────────────────────────

    # sendfile(): zero-copy file transfer (kernel reads + writes directly)
    sendfile on;

    # TCP_CORK: accumulate data until full MSS packet before sending
    # (Works only when sendfile is on)
    tcp_nopush on;

    # Disable Nagle's algorithm — send small packets immediately
    # (Good for low-latency APIs; less ideal for bulk file transfers)
    tcp_nodelay on;

    # ─────────────────────────────────────────────
    # KEEPALIVE DIRECTIVES
    # ─────────────────────────────────────────────

    # How long an idle keepalive connection remains open (seconds)
    keepalive_timeout 65;

    # Maximum requests on one keepalive connection (HTTP/1.1)
    keepalive_requests 1000;

    # ─────────────────────────────────────────────
    # BUFFER DIRECTIVES
    # ─────────────────────────────────────────────

    # Buffer for reading client request headers
    client_header_buffer_size 1k;

    # Buffer for large request headers (e.g., long cookies or auth tokens)
    large_client_header_buffers 4 8k;

    # Buffer for reading the client request body
    client_body_buffer_size 128k;

    # Maximum allowed client request body size (0 = unlimited)
    client_max_body_size 10m;

    # ─────────────────────────────────────────────
    # LOGGING FORMAT
    # ─────────────────────────────────────────────

    # Define a structured log format
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'rt=$request_time';

    # Write access logs (set to off for pure performance gain on static assets)
    access_log /var/log/nginx/access.log main;

    # ─────────────────────────────────────────────
    # GZIP COMPRESSION
    # ─────────────────────────────────────────────

    # Enable gzip compression
    gzip on;

    # Minimum response size to compress (bytes)
    gzip_min_length 256;

    # Compress these MIME types
    gzip_types text/plain text/css application/json application/javascript
               application/xml application/rss+xml image/svg+xml;

    # ─────────────────────────────────────────────
    # INCLUDE SERVER BLOCKS
    # ─────────────────────────────────────────────

    # Load all site configurations from conf.d directory
    include /etc/nginx/conf.d/*.conf;

    # Load enabled sites (Debian/Ubuntu convention)
    include /etc/nginx/sites-enabled/*;
}

```

---

## 5. The `server` Context (Virtual Hosts)

Each `server {}` block defines a **virtual host** — a logical server responding to specific domain names and ports:

```nginx
server {
    # Listen on port 80 for IPv4 and IPv6
    listen 80;
    listen [::]:80;

    # Domain names this virtual host handles
    server_name example.com www.example.com;

    # Document root for static files
    root /var/www/example.com/html;

    # Default file to serve when directory is requested
    index index.html index.htm;

    # Custom error pages
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;

    # Access log scoped to this virtual host
    access_log /var/log/nginx/example.com.access.log main;

    # Location blocks (URL routing) defined in next section
}

```

---

## 6. The `location` Context — URL Pattern Matching

The `location` block is where NGINX routes incoming requests. NGINX uses a **specific matching priority algorithm** — not simply "first match wins":

### Location Matching Priority (Highest to Lowest)

| Priority | Modifier | Syntax | Behavior |
| :---: | :--- | :--- | :--- |
| 1 | `=` | `location = /exact { }` | **Exact match** — highest priority, stops search |
| 2 | `^~` | `location ^~ /prefix { }` | **Prefix match** — if best prefix, stops search (no regex checked) |
| 3 | `~` | `location ~ \.php$ { }` | **Case-sensitive regex** |
| 4 | `~*` | `location ~* \.(jpg \| png)$ { }` | **Case-insensitive regex** |
| 5 | (none) | `location /prefix { }` | **Longest prefix match** (used if no regex matches) |

```nginx
server {
    server_name example.com;
    root /var/www/html;

    # Priority 1: Exact match for root — very fast, stops all searching
    location = / {
        return 200 "Exact root match\n";
    }

    # Priority 2: Prefix match for /static — skip regex, serve files directly
    location ^~ /static/ {
        expires 365d;
        add_header Cache-Control "public, immutable";
    }

    # Priority 3: Case-sensitive regex for PHP files
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        include fastcgi_params;
    }

    # Priority 4: Case-insensitive regex for images
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|avif)$ {
        expires 30d;
        add_header Cache-Control "public";
        access_log off;  # Don't log image requests
    }

    # Priority 5: Default prefix match
    location / {
        try_files $uri $uri/ =404;
    }
}

```

### The `try_files` Directive

`try_files` is the workhorse of modern NGINX routing:

```nginx

# Check if $uri exists as a file

# Then check if $uri/ exists as a directory (with index)

# If neither exists, return 404
location / {
    try_files $uri $uri/ =404;
}

# SPA routing: serve index.html for all non-file requests
location / {
    try_files $uri $uri/ /index.html;
}

# Proxy fallback: try file system first, then proxy
location / {
    try_files $uri @backend;
}

location @backend {
    proxy_pass http://app_servers;
}

```

---

## 7. Essential NGINX Variables

NGINX exposes hundreds of built-in variables. The most critical ones:

| Variable | Description | Example Value |
| :--- | :--- | :--- |
| `$host` | Request Host header | `example.com` |
| `$request_uri` | Full request URI with query string | `/api/users?page=2` |
| `$uri` | Normalized URI (no query string) | `/api/users` |
| `$args` | Query string | `page=2` |
| `$request_method` | HTTP method | `GET`, `POST` |
| `$status` | Response status code | `200`, `404` |
| `$remote_addr` | Client IP address | `192.168.1.1` |
| `$binary_remote_addr` | Binary IP (compact, for rate limiting) | (binary) |
| `$http_HEADER` | Any request header | `$http_authorization` |
| `$upstream_addr` | Backend server that handled the request | `10.0.0.1:8080` |
| `$request_time` | Total request processing time (seconds) | `0.042` |
| `$upstream_response_time` | Time to get upstream response | `0.038` |
| `$body_bytes_sent` | Response body bytes sent | `2048` |
| `$scheme` | Request scheme | `http`, `https` |
| `$server_name` | `server_name` that matched | `example.com` |
| `$proxy_add_x_forwarded_for` | Client IP + existing X-Forwarded-For chain | `1.2.3.4, 10.0.0.1` |

---

## 8. `include` Directives & Modular Configuration

Production NGINX configurations use `include` to split configs into maintainable files:

```nginx

# /etc/nginx/nginx.conf
http {
    # Global settings
    include /etc/nginx/conf.d/global-settings.conf;

    # Security headers (included in all server blocks)
    include /etc/nginx/snippets/security-headers.conf;

    # All virtual hosts
    include /etc/nginx/sites-enabled/*.conf;
}

```

```nginx

# /etc/nginx/snippets/security-headers.conf
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

```

---

## 9. Directive Inheritance Rules (Critical for Production)

Understanding inheritance prevents configuration surprises:

```nginx
http {
    # Defined at http level — applies to ALL servers by default
    gzip on;
    gzip_min_length 256;

    server {
        server_name api.example.com;

        # Override: disable gzip for this API server (JSON is already compact)
        gzip off;

        location /large-files/ {
            # Override again: re-enable gzip for this specific location
            gzip on;
            gzip_min_length 1024;
        }
    }

    server {
        server_name static.example.com;
        # Inherits gzip on from http context
    }
}

```

### Important: `add_header` Does NOT Inherit — It Replaces

```nginx
http {
    add_header X-Frame-Options "SAMEORIGIN";  # http level

    server {
        server_name example.com;
        add_header X-Content-Type-Options "nosniff";
        # ⚠️ WARNING: X-Frame-Options is now GONE for this server!
        # add_header in child context REPLACES all parent add_header directives
    }
}

```

**Fix**: Use a snippet file included in each location:

```nginx
location / {
    include /etc/nginx/snippets/security-headers.conf;
    # All headers in the snippet are applied
}

```

---

## 10. Production Configuration Validation Workflow

```bash

# Step 1: Test configuration syntax before any change
sudo nginx -t

# Step 2: View the full merged configuration (after all includes expanded)
sudo nginx -T | less

# Step 3: Apply changes with zero downtime
sudo nginx -s reload

# Step 4: Verify the running configuration
curl -I https://example.com

```

---

## 11. FinOps & Cloud Resource Cost Governance

### Configuration Modularization Reduces Operational Costs

A well-organized `conf.d/` + `snippets/` structure allows automation teams to apply security headers, compression, and caching rules across 50 virtual hosts by editing a single snippet file — reducing configuration change time from hours to minutes.

### Buffer Tuning Prevents Unnecessary Memory Waste

Default `client_body_buffer_size 128k` allocates 128 KB for request body buffering. For an API that only sends small JSON payloads (<4 KB), setting `client_body_buffer_size 16k` reduces per-connection memory usage by 87.5%.

---

## 12. Troubleshooting Common Configuration Mistakes

### Mistake 1: Order of `server_name` Matching

NGINX matches `server_name` by **longest specific string first**, not by order in file.
`server_name api.example.com *.example.com;` — `api.example.com` always matches explicitly.

### Mistake 2: Missing `default_server`

Without a `default_server`, NGINX serves the **first server block** to requests not matching any `server_name`. Always define explicitly:

```nginx
server {
    listen 80 default_server;
    server_name _;
    return 444;  # Drop unmatched connections silently
}

```

### Mistake 3: Overlapping Regex Location Blocks

Multiple regex `location ~` blocks can match the same URI. NGINX uses the **first matching regex in file order**. Ensure more specific regexes appear before general ones.

---

## References

### Official Documentation

* [NGINX Configuration File Structure](https://nginx.org/en/docs/beginners_guide.html) — Official beginner's guide to context hierarchy.
* [NGINX Core Directives Reference](https://nginx.org/en/docs/ngx_core_module.html) — Complete directive list with defaults.
* [NGINX HTTP Core Module](https://nginx.org/en/docs/http/ngx_http_core_module.html) — http/server/location directive reference.
* [NGINX Location Block Guide](https://www.digitalocean.com/community/tutorials/understanding-nginx-server-and-location-block-selection-algorithms) — Official community guide.
* [NGINX `try_files` Directive](https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files) — Official documentation.

### Authoritative Engineering Blogs

* [DigitalOcean: NGINX Location Block Selection Algorithms](https://www.digitalocean.com/community/tutorials/understanding-nginx-server-and-location-block-selection-algorithms) — Definitive guide to matching priority.
* [Martin Fjordvald: NGINX Optimization](https://nginx-book.readthedocs.io/) — In-depth configuration tuning guide.
* [Nginx Configuration Primer](https://www.nginx.com/resources/wiki/start/topics/examples/full/) — Real-world examples.
* [Cloudflare Blog: NGINX Configuration Best Practices](https://blog.cloudflare.com/) — Production NGINX at scale.
* [High Performance Browser Networking: Optimizing NGINX](https://hpbn.co/) — Ilya Grigorik's guide to HTTP/2 and NGINX.
