# Module 02: HTTP Server, Virtual Hosts & Location Block Matching

**Track:** Enterprise NGINX
**Category:** HTTP Server Configuration & URL Routing
**Status:** ✅ Production-Grade Reference Textbook (Zero to Master)

---

## 1. What Is a Virtual Host?

A **virtual host** (or virtual server) allows a single NGINX process to serve **multiple websites** on a single IP address and port. When a browser connects to port 443 on your server, it sends an HTTP `Host:` header (e.g., `Host: api.example.com`). NGINX reads this header and routes the request to the matching `server {}` block.

This is called **Name-Based Virtual Hosting** — the same IP address serves completely different websites based solely on the hostname.

```text
Browser request: GET / HTTP/1.1
                 Host: api.example.com
                 Connection: keep-alive

                          │
                          ▼
                 NGINX reads Host header
                          │
             ┌────────────┴────────────┐
             ▼                         ▼
server_name api.example.com    server_name app.example.com
(matches! → route to API)      (no match)

```

---

## 2. Complete Server Block Anatomy

```nginx

# /etc/nginx/sites-enabled/example.com.conf

server {
    # ─────────────────────────────────────────
    # LISTENING CONFIGURATION
    # ─────────────────────────────────────────

    # Listen on port 80 for IPv4
    listen 80;

    # Listen on port 80 for IPv6 (dual-stack)
    listen [::]:80;

    # ─────────────────────────────────────────
    # SERVER IDENTITY
    # ─────────────────────────────────────────

    # Domain names this server handles
    # Wildcards: *.example.com matches any subdomain
    server_name example.com www.example.com;

    # ─────────────────────────────────────────
    # DOCUMENT ROOT & INDEX
    # ─────────────────────────────────────────

    # Directory where static files are served from
    root /var/www/example.com/html;

    # Try these filenames when a directory is requested
    index index.html index.htm index.php;

    # ─────────────────────────────────────────
    # LOGGING
    # ─────────────────────────────────────────

    access_log /var/log/nginx/example.com.access.log main;
    error_log  /var/log/nginx/example.com.error.log warn;

    # ─────────────────────────────────────────
    # ERROR PAGES
    # ─────────────────────────────────────────

    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;

    location = /50x.html {
        root /usr/share/nginx/html;
    }

    # ─────────────────────────────────────────
    # LOCATION ROUTING
    # ─────────────────────────────────────────

    location / {
        try_files $uri $uri/ =404;
    }
}

```

---

## 3. Beginner Lab: Serving a Static Website

### Step 1: Create website directory

```bash

# Create document root
sudo mkdir -p /var/www/mysite.com/html

# Set correct ownership
sudo chown -R www-data:www-data /var/www/mysite.com

# Set read permissions
sudo chmod -R 755 /var/www/mysite.com

```

### Step 2: Create a simple HTML page

```bash
cat > /var/www/mysite.com/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>My NGINX Website</title></head>
<body>
    <h1>Hello from NGINX!</h1>
    <p>This page is served by NGINX on my server.</p>
</body>
</html>
EOF

```

### Step 3: Create the server block configuration

```bash
cat > /etc/nginx/sites-available/mysite.com << 'EOF'
server {
    listen 80;
    listen [::]:80;

    server_name mysite.com www.mysite.com;
    root /var/www/mysite.com/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

```

### Step 4: Enable the site and reload

```bash

# Create symlink in sites-enabled
sudo ln -s /etc/nginx/sites-available/mysite.com /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload NGINX
sudo nginx -s reload

# Test with curl
curl -I http://mysite.com

```

---

## 4. HTTPS Virtual Host with TLS

A production HTTPS virtual host always has two server blocks:

```nginx

# ─────────────────────────────────────────

# HTTP → HTTPS redirect server

# ─────────────────────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name example.com www.example.com;

    # Redirect all HTTP to HTTPS (301 permanent redirect)
    return 301 https://$host$request_uri;
}

# ─────────────────────────────────────────

# HTTPS server (main)

# ─────────────────────────────────────────
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    # Enable HTTP/2 multiplexing
    http2 on;

    server_name example.com www.example.com;
    root /var/www/example.com/html;

    # ─────────────────────────────────────────
    # TLS CERTIFICATES
    # ─────────────────────────────────────────

    # Certificate chain (cert + intermediate CA)
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;

    # Private key
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # ─────────────────────────────────────────
    # TLS SECURITY SETTINGS
    # ─────────────────────────────────────────

    # Only TLS 1.2 and 1.3 (drop old insecure versions)
    ssl_protocols TLSv1.2 TLSv1.3;

    # Prefer strong cipher suites
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;

    # Prefer server cipher order
    ssl_prefer_server_ciphers off;

    # SSL session cache (10m ≈ 40,000 sessions)
    ssl_session_cache shared:SSL:10m;

    # Session timeout
    ssl_session_timeout 1d;

    # ─────────────────────────────────────────
    # HSTS (force browsers to always use HTTPS)
    # ─────────────────────────────────────────
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    location / {
        try_files $uri $uri/ =404;
    }
}

```

---

## 5. Multiple Virtual Hosts on One Server

```nginx

# /etc/nginx/conf.d/api.conf
server {
    listen 443 ssl http2;
    server_name api.example.com;
    ssl_certificate /etc/ssl/api.example.com.crt;
    ssl_certificate_key /etc/ssl/api.example.com.key;

    location / {
        proxy_pass http://api_backend;
    }
}

# /etc/nginx/conf.d/app.conf
server {
    listen 443 ssl http2;
    server_name app.example.com;
    ssl_certificate /etc/ssl/app.example.com.crt;
    ssl_certificate_key /etc/ssl/app.example.com.key;
    root /var/www/app.example.com;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

# /etc/nginx/conf.d/default.conf

# Catch-all for unmatched domain names
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/default.crt;
    ssl_certificate_key /etc/ssl/default.key;

    # Return empty response — don't reveal server infrastructure
    return 444;
}

```

---

## 6. Advanced Location Matching Patterns

### Named Locations for Internal Redirects

```nginx
server {
    location / {
        # Try file system first, then hand off to named location @proxy
        try_files $uri @proxy;
    }

    # Named location — cannot be called by external clients
    location @proxy {
        proxy_pass http://backend:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

```

### Nested Locations

```nginx
server {
    location /api/ {
        # General API handling
        proxy_pass http://api_backend;

        location /api/v1/uploads {
            # Override: larger body size for this endpoint
            client_max_body_size 100m;
            proxy_pass http://upload_backend;
        }
    }
}

```

### File Extension Routing

```nginx
server {
    root /var/www/html;

    # PHP processing
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    # Static assets with aggressive caching
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff2|woff|ttf|otf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary "Accept-Encoding";
        access_log off;
    }

    # Deny access to hidden files (e.g., .htaccess, .git)
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}

```

---

## 7. SPA (Single Page Application) Configuration

Modern SPAs (React, Vue, Angular) use client-side routing. Any URL like `/dashboard/settings` needs to return `index.html`:

```nginx
server {
    listen 443 ssl http2;
    server_name app.example.com;
    root /var/www/spa/dist;
    index index.html;

    # Serve index.html for all routes (client handles routing)
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API proxy (don't intercept /api/* with SPA routing)
    location /api/ {
        proxy_pass http://backend:3000;
        proxy_set_header Host $host;
    }

    # Aggressive cache for hashed assets (Vite/webpack output)
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary "Accept-Encoding";
    }
}

```

---

## 8. Complete CLI Reference for Virtual Host Management

```bash

# ─────────────────────────────────────────────

# SITE MANAGEMENT (Debian/Ubuntu)

# ─────────────────────────────────────────────

# Create new site configuration
sudo nano /etc/nginx/sites-available/newsite.com

# Enable site (create symlink)
sudo ln -s \
    /etc/nginx/sites-available/newsite.com \
    /etc/nginx/sites-enabled/newsite.com

# Disable site (remove symlink)
sudo rm /etc/nginx/sites-enabled/newsite.com

# Test configuration
sudo nginx -t

# Reload (apply changes)
sudo nginx -s reload

# ─────────────────────────────────────────────

# SSL CERTIFICATE WITH LET'S ENCRYPT

# ─────────────────────────────────────────────

# Install Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# Obtain certificate and auto-configure NGINX
sudo certbot --nginx -d example.com -d www.example.com

# Test auto-renewal
sudo certbot renew --dry-run

# Check certificate expiry
sudo certbot certificates

# ─────────────────────────────────────────────

# TESTING VIRTUAL HOSTS

# ─────────────────────────────────────────────

# Test HTTP response headers
curl -I http://example.com

# Test HTTPS with detailed TLS info
curl -v https://example.com 2>&1 | head -40

# Test virtual host matching without DNS
curl -H "Host: example.com" http://SERVER_IP/

# Check certificate details
openssl s_client \
    -connect example.com:443 \
    -servername example.com \
    </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -dates

```

---

## 9. FinOps & Cloud Resource Cost Governance

### Multi-Domain TLS with SNI Eliminates Certificate Costs

Server Name Indication (SNI) allows a single NGINX server to serve **different TLS certificates** for different domains on the same IP address. Before SNI (pre-2003), each domain required a dedicated IP — at $4-$8/month per Elastic IP on AWS. A 20-domain setup saves $80-$160/month.

### Wildcard Certificates + NGINX = Zero Per-Domain Overhead

Using a single `*.example.com` Let's Encrypt wildcard certificate serves any subdomain without individual certificate management, reducing certificate renewal automation from 20 cron jobs to 1.

### Aggressive Cache Headers for Static Assets Slash CDN Egress

Setting `expires 1y; add_header Cache-Control "public, immutable"` for Vite/webpack hashed assets means browsers cache them for one year. This eliminates 90%+ of CDN origin fetch requests, reducing Cloudfront origin data transfer from 1 TB/month to 100 GB/month (saving ~$90/month).

---

## 10. Troubleshooting Virtual Host Issues

### Issue: Wrong Virtual Host Serves the Request

**Symptom**: Requests to `api.example.com` serve content from `www.example.com`.
**Diagnosis**:

```bash
curl -v -H "Host: api.example.com" http://SERVER_IP/ 2>&1 | grep "Server:"

```

**Root Cause**: NGINX serves the **first server block** when no `server_name` matches.
**Fix**: Add a `default_server` catch-all block (see section 5 above).

### Issue: HTTPS Serving HTTP Content

**Symptom**: Browser shows "Mixed Content" warnings.
**Cause**: Embedded resources (images, scripts) use `http://` URLs.
**Fix**: Add `add_header Content-Security-Policy "upgrade-insecure-requests";`

### Issue: ERR_TOO_MANY_REDIRECTS

**Cause**: HTTPS redirect loop — NGINX behind a load balancer receives HTTP but redirects to HTTPS forever.
**Fix**: Trust the `X-Forwarded-Proto` header:

```nginx
server {
    listen 80;
    if ($http_x_forwarded_proto = "http") {
        return 301 https://$host$request_uri;
    }
}

```

---

## References

### Official Documentation

* [NGINX HTTP Server Module](https://nginx.org/en/docs/http/ngx_http_core_module.html) — server, location directive reference.
* [NGINX Server Block Selection](https://nginx.org/en/docs/http/server_names.html) — Official `server_name` matching documentation.
* [Let's Encrypt Certbot NGINX](https://certbot.eff.org/instructions?ws=nginx) — Official TLS certificate automation guide.
* [NGINX SSL Termination](https://docs.nginx.com/nginx/admin-guide/security-controls/terminating-ssl-http/) — Official TLS configuration guide.
* [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/#server=nginx) — Recommended cipher suite configurations.

### Authoritative Engineering Blogs

* [DigitalOcean: How to Set Up NGINX Server Blocks](https://www.digitalocean.com/community/tutorials/how-to-set-up-nginx-server-blocks-virtual-hosts-on-ubuntu-20-04) — Comprehensive virtual host tutorial.
* [High Performance Browser Networking: TLS](https://hpbn.co/transport-layer-security-tls/) — TLS performance optimization for NGINX.
* [Cloudflare: TLS 1.3 Performance](https://blog.cloudflare.com/rfc-8446-aka-tls-1-3/) — 0-RTT and TLS 1.3 improvements.
* [Scott Helme: HSTS and Preloading](https://scotthelme.co.uk/hsts-the-missing-link-in-tls/) — HSTS security configuration guide.
* [Troy Hunt: Everything You Need to Know About HTTPS](https://www.troyhunt.com/the-beginners-guide-to-breaking-website/) — Web HTTPS migration guide.
