# Module 06: Caching Mechanisms, Cache Keys, Purging & Microcaching

**Track:** Enterprise NGINX  
**Category:** Response Caching & Performance Optimization

---

## What NGINX Caching Does

NGINX can store backend responses on disk (or in memory) and serve them directly to subsequent clients without touching the backend server at all. For a response that takes 200ms to generate on your backend, caching means the 2nd through 10,000th requests each take 2ms — served from disk.

This is **proxy caching**: NGINX caches what it receives from an `upstream` backend. It is distinct from browser caching (controlled by `Cache-Control` headers you send to clients) or CDN caching (external services like Cloudflare). You control NGINX proxy caching entirely in your configuration.

---

## Setting Up the Cache Zone

Before any server block, define a cache storage zone in the `http` context:

```nginx
http {
    # proxy_cache_path defines where cache files live on disk
    # levels=1:2   creates a two-level directory tree under the path
    #              (prevents having too many files in one directory)
    # keys_zone=my_cache:10m  — the shared memory zone that holds cache keys
    #              10m = 10MB, stores ~80,000 key entries
    # max_size=2g  — maximum total cache size on disk; oldest files evicted first
    # inactive=60m — remove files not accessed in 60 minutes regardless of TTL
    # use_temp_path=off — write cache files directly without a temp-file copy step
    proxy_cache_path /var/cache/nginx
        levels=1:2
        keys_zone=api_cache:10m
        max_size=2g
        inactive=60m
        use_temp_path=off;
}
```

---

## Enabling Cache in a Location Block

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    location /api/v1/ {
        proxy_pass http://backend_servers;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;

        # ── Cache configuration ───────────────────────────────────────────
        proxy_cache            api_cache;

        # Cache 200 responses for 10 minutes; 404 for 1 minute
        proxy_cache_valid      200 10m;
        proxy_cache_valid      404  1m;

        # Only cache GET and HEAD requests (never cache POST/PUT/DELETE)
        proxy_cache_methods    GET HEAD;

        # Cache key: what makes two requests "the same"?
        # This key caches per scheme + host + URI (excluding query string)
        proxy_cache_key        "$scheme$host$request_uri";

        # Serve stale cache while revalidating in background
        proxy_cache_use_stale  error timeout updating;

        # Lock: if a cache entry is being populated, queue other requests
        # rather than letting all of them hit the backend simultaneously
        proxy_cache_lock       on;
        proxy_cache_lock_timeout 5s;

        # Bypass cache when client sends no-cache
        proxy_cache_bypass     $http_pragma $http_authorization;

        # Add header showing whether response came from cache
        add_header             X-Cache-Status $upstream_cache_status;

        # Set Cache-Control for downstream clients
        add_header             Cache-Control "public, max-age=600";
    }
}
```

The `$upstream_cache_status` variable reports: `HIT`, `MISS`, `BYPASS`, `EXPIRED`, `STALE`, `UPDATING`, or `REVALIDATED`. Logging this tells you your cache hit rate.

---

## Cache Keys: The Most Important Decision

The cache key determines when NGINX considers two requests identical and serves the cached response. Choosing the wrong key causes either:
- **Over-caching**: serving the same response to requests that should receive different data
- **Under-caching**: treating identical requests as different, defeating caching

```nginx
# Scenario 1: Public API — cache by URL only
# All users requesting /api/products/123 get the same response
proxy_cache_key "$scheme$host$request_uri";

# Scenario 2: Authenticated API — cache per user
# Include the Authorization header so each user's data is cached separately
proxy_cache_key "$scheme$host$request_uri$http_authorization";

# Scenario 3: Content-negotiated API — cache per Accept header
# /api/data.json and /api/data.xml are different cached entries
proxy_cache_key "$scheme$host$request_uri$http_accept";

# Scenario 4: Localized content — cache per language
proxy_cache_key "$scheme$host$request_uri$http_accept_language";
```

---

## Microcaching: Caching for Just 1 Second

For dynamic pages generated from a database, even caching for 1 second can massively reduce backend load during traffic spikes. If 5,000 users hit a page within the same second, NGINX fetches it once from the backend and serves the cached copy to all 4,999 others.

```nginx
proxy_cache_path /var/cache/nginx/micro
    levels=1:2
    keys_zone=micro_cache:5m
    max_size=500m
    inactive=2m
    use_temp_path=off;

server {
    location / {
        proxy_pass http://app_servers;

        proxy_cache       micro_cache;
        proxy_cache_valid 200 1s;        # Cache for exactly 1 second
        proxy_cache_key   "$scheme$host$request_uri";
        proxy_cache_use_stale updating;  # Serve stale while refreshing
        proxy_cache_lock  on;

        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

With `proxy_cache_use_stale updating`, when the 1-second TTL expires, one request fetches a new copy from the backend while all concurrent requests receive the (now-stale) previous response. This prevents the **cache stampede** problem.

---

## Cache Bypass: Skipping the Cache Conditionally

There are situations where you must bypass the cache:
- Authenticated requests with personal data
- Requests with `Cache-Control: no-cache` from clients
- Admin users who need real-time data

```nginx
# Define a bypass variable: 1 = bypass cache, 0 = use cache
map $http_cookie $no_cache {
    default           0;
    "~*session_token" 1;   # Users with a session cookie bypass cache
}

map $request_method $bypass_on_write {
    default 0;
    POST    1;              # Never cache POST responses
    PUT     1;
    DELETE  1;
    PATCH   1;
}

location /api/ {
    proxy_cache       api_cache;
    proxy_cache_valid 200 5m;
    proxy_no_cache    $no_cache $bypass_on_write;
    proxy_cache_bypass $no_cache $bypass_on_write;
}
```

`proxy_no_cache` controls whether the response is **stored**. `proxy_cache_bypass` controls whether the cache is **consulted** for the incoming request. Setting both ensures that write requests neither read from nor write to the cache.

---

## Cache Purging

NGINX open source does not have built-in cache purge. To invalidate a cached entry you can either wait for its TTL to expire or delete the file from disk.

```bash
# Find and delete a specific cached URL
# Cache files are stored with a hash of the cache key as the filename

# Method 1: Delete all cache files (nuclear option)
rm -rf /var/cache/nginx/*
nginx -s reload

# Method 2: Find the file for a specific key
# The cache filename is the MD5 hash of the cache key
CACHE_KEY="httpexample.com/api/products/123"
echo -n "$CACHE_KEY" | md5sum
# Use the hash to find and delete the specific file

# Method 3: Use the ngx_cache_purge module (if compiled in)
# Sends a PURGE request to force NGINX to remove the cache entry
curl -X PURGE https://example.com/api/products/123
```

For production cache purging, the `ngx_cache_purge` module adds a `proxy_cache_purge` directive that accepts a special PURGE HTTP method:

```nginx
location ~ /purge(/.*) {
    # Only allow internal network to trigger purges
    allow 10.0.0.0/8;
    deny  all;
    proxy_cache_purge api_cache "$scheme$host$1";
}
```

---

## Checking Cache Performance

```bash
# Real-time cache hit rate from access log
tail -f /var/log/nginx/access.log \
    | awk '/X-Cache-Status/ {print $NF}' \
    | sort | uniq -c

# Count HITs vs MISSes from existing log
awk '{print $NF}' /var/log/nginx/access.log \
    | grep -E "^(HIT|MISS|BYPASS|EXPIRED)" \
    | sort | uniq -c

# Check disk usage of cache
du -sh /var/cache/nginx/

# List largest cached files
find /var/cache/nginx -type f -printf '%s %p\n' | sort -rn | head -20
```

---

## FinOps: How Caching Cuts Backend Costs

A Node.js API instance on a `t3.medium` costs $0.0416/hour. If your product catalog endpoint is cacheable for 5 minutes and receives 1,000 req/min, without caching you need enough backend capacity to handle 1,000 req/min continuously. With a 5-minute cache, the backend handles 1 request per 5 minutes (0.2 req/min) for that endpoint — a 5,000× reduction in backend load for that endpoint.

In practice, caching 30% of your endpoints with suitable TTLs typically allows a 40-60% reduction in backend instance count, saving hundreds to thousands of dollars monthly depending on scale.

---

## Troubleshooting Cache Problems

**Cache never hitting (all responses show MISS)**

Check that `proxy_cache_bypass` and `proxy_no_cache` are not accidentally always evaluating to a truthy value. Add temporary logging:

```nginx
add_header X-Cache-Bypass-Reason "$no_cache $bypass_on_write" always;
```

Also verify the response does not contain `Cache-Control: no-store` or `Set-Cookie` headers from the backend. By default NGINX does not cache responses with `Set-Cookie` or `Cache-Control: private`.

**Stale content being served after backend update**

Your TTL is too long for your use case. Either lower `proxy_cache_valid`, add cache purging, or use ETags/Last-Modified with `proxy_cache_revalidate on` so NGINX sends conditional requests to the backend.

**`proxy_cache_use_stale` serving expired content indefinitely**

`proxy_cache_use_stale updating` serves stale content only when a background refresh is in progress. If the background refresh itself fails, content stops being served stale. Combine with `error timeout` to also serve stale when the backend is completely unreachable:
```nginx
proxy_cache_use_stale error timeout updating;
```
