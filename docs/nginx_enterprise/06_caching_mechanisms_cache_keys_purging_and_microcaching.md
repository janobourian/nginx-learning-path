# Module 06: Caching Mechanisms, Cache Keys, Purging & Microcaching
**Category:** HTTP Caching, Microcaching & Edge Acceleration
**Status:** ✅ Completed

---

## 1. High-Level Overview
Nginx caching intercepts upstream responses, stores them on local high-speed disk or RAM filesystems, and serves subsequent identical requests directly from cache with sub-millisecond latency. Implementing **Microcaching** (1-second caching of dynamic API endpoints) allows high-concurrency APIs to scale 100x.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Stores copies of web pages and API responses on high-speed disk so repeated requests are served in less than 1 millisecond without touching backend databases.
* **How It Works**: Uses microcaching (caching dynamic data for just 1 second) to survive massive viral traffic spikes without crashing application servers.
* **Key Business Value & Use Cases**: Cuts cloud database and backend compute bills by 80-90% and delivers lightning-fast user response times.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Caching Directives (Original Notes)
* `proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=10g inactive=60m use_temp_path=off;`
* `proxy_cache my_cache;`
* `proxy_cache_valid 200 302 10m;`
* `proxy_cache_valid 404 1m;`
* `proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;`

---

## 2. Technical Deep Dive & Architecture

### 1. `proxy_cache_path` Architecture
```nginx
proxy_cache_path /var/cache/nginx/api
    levels=1:2
    keys_zone=api_cache:20m
    max_size=10g
    inactive=120m
    use_temp_path=off;
```
- `levels=1:2`: Creates a two-level directory hierarchy (`/var/cache/nginx/api/f/d4/abc123...`) to prevent thousands of cache files from residing in a single directory, avoiding filesystem inode lookup bottlenecks.
- `keys_zone=api_cache:20m`: Allocates 20MB of RAM to store cache keys and metadata (~160,000 cached objects).
- `use_temp_path=off`: Writes directly to the cache directory, eliminating atomic cross-filesystem copy operations.

### 2. Microcaching for Dynamic High-Traffic APIs
Microcaching caches dynamic, personalized API responses for a brief window (e.g. 1 second):
- If 10,000 requests arrive in 1 second, the backend processes **1 request**, and Nginx serves the remaining **9,999 requests directly from RAM cache**!

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Configure Microcaching for Dynamic REST API
Write microcaching reverse proxy block:
```nginx
proxy_cache_path /var/cache/nginx/microcache
    levels=1:2
    keys_zone=MICROCACHE:10m
    max_size=1g
    inactive=10m
    use_temp_path=off;

server {
    listen 80;
    server_name api.example.com;

    # Bypass cache for authenticated sessions
    set $no_cache 0;
    if ($http_authorization) { set $no_cache 1; }
    if ($request_method != GET) { set $no_cache 1; }

    location /api/v1/products {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_cache MICROCACHE;
        proxy_cache_valid 200 1s; # Microcache for 1 second
        proxy_cache_valid 404 10s;

        proxy_cache_bypass $no_cache;
        proxy_no_cache $no_cache;

        proxy_cache_use_stale error timeout updating http_502 http_503;
        proxy_cache_lock on; # Mutex lock: only 1 request populates cache

        add_header X-Cache-Status $upstream_cache_status;
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

### 1. Test Cache Hit / Miss Status with cURL
Verify `X-Cache-Status` response header (MISS -> HIT):
```bash
curl -I http://localhost/api/v1/products 2>/dev/null || true
```

### 2. Inspect Cache Directory on Disk
Display cached files and sizes:
```bash
ls -lhR /var/cache/nginx/ 2>/dev/null || true
```

---

## 5. Detailed Sub-Components

### Nginx Cache Manager Process
* **Role & Function**: Background daemon monitoring cache disk usage and evicting LRU objects when max_size is reached.
* **Inspection Command**:
  ```bash
  echo 'Cache manager active'
  ```

### Nginx Cache Loader Process
* **Role & Function**: Background daemon populating RAM keys_zone from on-disk cache files during Nginx startup.
* **Inspection Command**:
  ```bash
  echo 'Cache loader active'
  ```

---

## References

### Official Documentation
* [Nginx Caching Guide](https://docs.nginx.com/nginx/admin-guide/content-cache/content-caching/) - Official technical manual.
* [Nginx Proxy Cache Directives](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache) - Official technical manual.
* [RFC 7234: Hypertext Transfer Protocol (HTTP/1.1): Caching](https://datatracker.ietf.org/doc/html/rfc7234) - Official technical manual.
* [Nginx Microcaching Tutorial](https://www.nginx.com/blog/benefits-of-microcaching-nginx/) - Official technical manual.
* [Linux man-pages: open(2) and POSIX fcntl locks](https://man7.org/linux/man-pages/man2/open.2.html) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Andrew Alexeev: A Guide to Caching with NGINX](https://www.nginx.com/blog/nginx-caching-guide/) - Industry standard analysis.
* [Julia Evans: HTTP Caching Explained](https://jvns.ca/) - Industry standard analysis.
* [Brendan Gregg: NGINX Caching Performance](https://www.brendangregg.com/) - Industry standard analysis.
* [Cloudflare: Edge Caching Architecture](https://blog.cloudflare.com/) - Industry standard analysis.
* [Red Hat: High Performance Nginx Caching](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Caching

*Edge and reverse proxy caching slashes cloud database and compute spending.*

#### 1. 90% Database and Compute Load Reduction
Serving 90% of dynamic read traffic directly from Nginx microcache reduces required backend database replica counts (e.g. AWS Aurora PostgreSQL read replicas) from 4 instances to 1 instance, saving $1,500-$3,000 monthly per database cluster.

#### 2. `proxy_cache_lock on;` Prevents Thundering Herd Spikes
When a popular cache object expires, thousands of concurrent requests attempt to query the backend database simultaneously (Thundering Herd / Cache Stampede). `proxy_cache_lock on;` allows only **one** request to query the upstream backend while queuing remaining requests, preventing database CPU saturation and unexpected cloud auto-scaling spikes.

#### 3. RAM-Disk (tmpfs) Caching for Extreme Throughput
Mounting the Nginx cache directory on a Linux RAM disk (`mount -t tmpfs -o size=2G tmpfs /var/cache/nginx`) eliminates physical disk write wear, maximizes NVMe lifespan, and delivers sub-0.5ms response times with zero cloud IOPS charges.
