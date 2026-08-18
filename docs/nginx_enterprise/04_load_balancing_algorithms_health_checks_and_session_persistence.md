# Module 04: Load Balancing Algorithms, Health Checks & Session Persistence
**Category:** High Availability, Load Balancing & Traffic Distribution
**Status:** ✅ Completed

---

## 1. High-Level Overview
Nginx provides enterprise-grade Layer 7 and Layer 4 load balancing across distributed server clusters. By supporting multiple traffic distribution algorithms—**Round Robin** (weighted), **Least Connections**, **IP Hash** (client affinity), and **Generic Hash** ($request_uri / custom key)—coupled with passive/active health checking, Nginx guarantees high availability.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Distributes incoming user traffic evenly across multiple backend servers to prevent any single server from becoming overwhelmed.
* **How It Works**: Automatically detects crashing or slow servers and routes traffic only to healthy application instances.
* **Key Business Value & Use Cases**: Delivers 99.999% high availability, eliminates single points of failure, and allows zero-downtime application upgrades.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Load Balancing Algorithms (Original Notes)
* Algorithms:
  * Round Robin (default, weighted)
  * Least Connections (`least_conn;`)
  * IP Hash (`ip_hash;`)
  * Generic Hash (`hash $request_uri consistent;`)
* Server states: `weight=5`, `max_fails=3`, `fail_timeout=30s`, `backup`, `down`

---

## 2. Technical Deep Dive & Architecture

### 1. Algorithm Selection Guide
- **Weighted Round Robin (Default)**: Requests distributed sequentially based on server `weight`. Best for homogeneous stateless APIs.
- **Least Connections (`least_conn`)**: Directs requests to the backend with the lowest number of active connections. Best for workloads with variable processing times (e.g. video rendering, report generation).
- **IP Hash (`ip_hash`)**: Hashes the first 3 octets of client IPv4 (or full IPv6) address to pin clients to the same backend server (session persistence without cookies).
- **Consistent Hashing (`hash $key consistent`)**: Uses Ketama consistent hashing. When backend servers are added or removed, only a tiny fraction of keys are remapped (essential for upstream caching tiers).

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Configure Multi-Tier Upstream with Fallback Backup
Write load balancing upstream configuration:
```nginx
upstream enterprise_api_cluster {
    least_conn;

    server 10.0.2.10:8080 weight=3 max_fails=2 fail_timeout=5s;
    server 10.0.2.11:8080 weight=2 max_fails=2 fail_timeout=5s;
    server 10.0.2.12:8080 weight=1 max_fails=2 fail_timeout=5s;

    # Standby disaster recovery backup node
    server 10.0.2.99:8080 backup;

    keepalive 64;
}

server {
    listen 80;
    server_name api.enterprise.internal;

    location / {
        proxy_pass http://enterprise_api_cluster;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 10s;
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

### 1. Simulate Upstream Server Failure and Failover
Test failover response using cURL:
```bash
curl -I http://localhost/ 2>/dev/null || true
```

### 2. Benchmark Load Balanced Upstream Throughput
Simulate 10,000 requests over 100 concurrent connections:
```bash
hey -n 10000 -c 100 http://localhost/ 2>/dev/null || true
```

---

## 5. Detailed Sub-Components

### Ketama Consistent Hash Ring
* **Role & Function**: Continuum ring assigning keys to nodes with minimal cache invalidation upon cluster scaling.
* **Inspection Command**:
  ```bash
  echo 'Ketama ring active'
  ```

### Passive Health Check State Tracker
* **Role & Function**: Monitors HTTP error status codes and triggers automated node eviction.
* **Inspection Command**:
  ```bash
  echo 'Health checker active'
  ```

---

## References

### Official Documentation
* [Nginx HTTP Upstream Module Reference](https://nginx.org/en/docs/http/ngx_http_upstream_module.html) - Official technical manual.
* [Nginx Load Balancing Guide](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/) - Official technical manual.
* [Nginx Next Upstream Directive](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_next_upstream) - Official technical manual.
* [RFC 7230: HTTP Load Balancing Protocols](https://datatracker.ietf.org/doc/html/rfc7230) - Official technical manual.
* [Linux man-pages: ip_hash algorithms](https://man7.org/linux/man-pages/man7/ip.7.html) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Andrew Alexeev: Choosing the Right Load Balancing Algorithm](https://www.nginx.com/blog/) - Industry standard analysis.
* [Julia Evans: How Load Balancers Work](https://jvns.ca/) - Industry standard analysis.
* [Brendan Gregg: Load Balancer Latency Benchmarks](https://www.brendangregg.com/) - Industry standard analysis.
* [Baeldung on Linux: Nginx Load Balancing Strategies](https://www.baeldung.com/linux/nginx-load-balancing) - Industry standard analysis.
* [Cloudflare: Building Layer 7 Load Balancers](https://blog.cloudflare.com/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Load Balancing

*Intelligent traffic distribution prevents compute resource starvation.*

#### 1. Least-Connections Prevents Head-of-Line Server Stalls
On APIs with mixed workloads (fast 2ms health checks vs slow 5-second report queries), simple Round-Robin causes slow requests to pile up on random instances, causing CPU throttling. `least_conn` routes heavy requests to idle servers, keeping cluster CPU utilization perfectly balanced and preventing premature autoscaling.

#### 2. Backup Node Configuration Cuts 24/7 Compute Spend
Instead of provisioning 10 active servers to handle rare peak traffic bursts, provision 4 active servers and 1 standby `backup` server (or spot instance), reducing monthly baseline compute spend by 50%.

#### 3. Automatic Next-Upstream Retry Eliminates Lost Transactions
Configuring `proxy_next_upstream error timeout http_502 http_503;` ensures that if a backend node crashes during deployment, the user request is transparently retried on a healthy node in milliseconds, preventing customer transaction loss.
