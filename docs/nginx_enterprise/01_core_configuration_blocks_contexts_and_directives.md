# Module 01: Core Configuration Blocks, Contexts & Directive Inheritance
**Category:** Nginx Configuration Architecture & Syntax
**Status:** ✅ Completed

---

## 1. High-Level Overview
Nginx configuration files (`nginx.conf`) follow a hierarchical block structure consisting of distinct nested contexts (`main`, `events`, `http`, `server`, `location`, `upstream`, `stream`). Directives define operational behaviors, and understanding inheritance rules (parent-to-child cascading and replacement) is essential for robust infrastructure as code.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Establishes the structural rules for configuring web routing, security limits, and domain names inside Nginx configuration files.
* **How It Works**: Uses nested configuration blocks to define global server settings, individual websites (virtual hosts), and specific web page paths.
* **Key Business Value & Use Cases**: Eliminates configuration duplication, prevents syntax bugs, and ensures secure, maintainable web server infrastructure.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Configuration Directives (Original Notes)
* Main context: `user`, `worker_processes`, `error_log`, `pid`
* Events context: `worker_connections`
* HTTP context: `include`, `default_type`, `sendfile`, `keepalive_timeout`

---

## 2. Technical Deep Dive & Architecture

### 1. Hierarchical Context Tree
```
main (global)
 ├── events { ... }
 ├── stream { ... } (TCP/UDP Proxying)
 └── http { ... }
      ├── upstream backend_pool { ... }
      └── server { ... } (Virtual Host)
           ├── location / { ... }
           └── location /api/ { ... }
```

### 2. Directive Inheritance Rules
- **Standard Directives (Scalar values)**: Inherited from parent context unless explicitly overridden in the child block (e.g. `client_max_body_size 10M;`).
- **Array / List Directives (`add_header`, `proxy_set_header`)**: Array directives are **NOT** merged. If a child block defines a single `add_header`, all `add_header` directives from parent contexts are completely ignored!

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Write a Hardened Master Configuration
Create baseline `nginx.conf`:
```nginx
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 8192;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main_json escape=json '{'
        '"time_local":"$time_local",'
        '"remote_addr":"$remote_addr",'
        '"request":"$request",'
        '"status": "$status",'
        '"body_bytes_sent":"$body_bytes_sent",'
        '"request_time":"$request_time",'
        '"http_referrer":"$http_referer",'
        '"http_user_agent":"$http_user_agent"'
    '}';

    access_log /var/log/nginx/access.log main_json;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/conf.d/*.conf;
}
```

### Step 2: Validate Syntax
Test configuration:
```bash
nginx -t
```

---

## 4. Pure Escaped CLI Snippets (Production Operations)

### 1. Dump Active Evaluated Configuration
Display complete compiled configuration with all includes resolved:
```bash
sudo nginx     -T
```

### 2. Format Nginx Configuration Files
Lint and format configuration syntax:
```bash
nginxfmt -i /etc/nginx/nginx.conf 2>/dev/null || true
```

---

## 5. Detailed Sub-Components

### MIME Type Registry (mime.types)
* **Role & Function**: Maps file extensions (.html, .json, .wasm) to standard Content-Type HTTP headers.
* **Inspection Command**:
  ```bash
  head -n 20 /etc/nginx/mime.types 2>/dev/null || true
  ```

### File Descriptor Limit (worker_rlimit_nofile)
* **Role & Function**: Kernel resource limit setting the maximum number of open files per worker.
* **Inspection Command**:
  ```bash
  ulimit -n
  ```

---

## References

### Official Documentation
* [Nginx Configuration File Syntax](https://nginx.org/en/docs/beginners_guide.html#conf_structure) - Official technical manual.
* [Nginx HTTP Core Module Reference](https://nginx.org/en/docs/http/ngx_http_core_module.html) - Official technical manual.
* [Nginx Events Module Reference](https://nginx.org/en/docs/ngx_core_module.html#events) - Official technical manual.
* [Linux man-pages: nginx(8)](https://man7.org/linux/man-pages/man8/nginx.8.html) - Official technical manual.
* [Nginx Includes and Modularity Guide](https://docs.nginx.com/nginx/admin-guide/basic-functionality/managing-configuration-files/) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [DigitalOcean: Understanding Nginx Server and Location Block Selection](https://www.digitalocean.com/community/tutorials/understanding-nginx-server-and-location-block-selection-algorithms) - Industry standard analysis.
* [Andrew Alexeev: NGINX Configuration Best Practices](https://www.nginx.com/blog/) - Industry standard analysis.
* [Julia Evans: Understanding Nginx Configuration](https://jvns.ca/) - Industry standard analysis.
* [Baeldung on Linux: Nginx Configuration Architecture](https://www.baeldung.com/linux/) - Industry standard analysis.
* [Red Hat: Nginx on Enterprise Linux](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Core Configuration

*Kernel sendfile and socket optimizations eliminate CPU copy cycles.*

#### 1. Zero-Copy `sendfile on;` and `tcp_nopush on;`
Enabling `sendfile on;` allows the Linux kernel to transfer static files directly from the page cache to the network card socket via DMA (Direct Memory Access), bypassing user-space buffer copies entirely. Combining this with `tcp_nopush on;` ensures full network packets (MTU 1500 bytes) are sent, reducing network packet overhead and CPU cycles by 35%.

#### 2. Tuning `keepalive_timeout` to Prevent Thread Exhaustion
An excessively long `keepalive_timeout` (e.g. 300 seconds) holds idle connection sockets open unnecessarily, consuming kernel socket memory. Tuning keepalive to 65 seconds balances persistent connection reuse with timely resource reclamation.

#### 3. Multi-Tenant Server Consolidation
Using virtual host `server {}` blocks to host hundreds of internal domain names on a single Nginx proxy instance eliminates the recurring infrastructure cost of provisioning dedicated load balancers for every internal tool.
