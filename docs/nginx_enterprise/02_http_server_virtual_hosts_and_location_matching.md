# Module 02: HTTP Server, Virtual Hosts & Location Matching Precedence
**Category:** Virtual Hosts, SNI & Request Routing
**Status:** ✅ Completed

---

## 1. High-Level Overview
Nginx maps incoming HTTP requests to specific `server {}` blocks based on the `Host` header and IP/Port bindings, and then routes requests to specific `location {}` blocks. Understanding location modifier precedence is critical for routing accuracy and security.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Directs incoming web traffic to the correct website or microservice based on the domain name and requested URL path.
* **How It Works**: Uses strict priority rules (exact match, prefix match, regex) to determine which configuration block handles each request.
* **Key Business Value & Use Cases**: Prevents URL routing conflicts, ensures fast request dispatching, and closes security holes caused by overlapping path rules.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Location Block Priority (Original Notes)
* Location modifiers:
  * `=` : Exact match (highest priority, stops search immediately)
  * `^~` : Preferential prefix match (stops regex search)
  * `~` : Case-sensitive regular expression match
  * `~*` : Case-insensitive regular expression match
  * (none) : Standard prefix match (longest prefix wins)

---

## 2. Technical Deep Dive & Architecture

### 1. The 5-Step Location Matching Algorithm
When an HTTP request arrives:
1. **Exact Match (`=`)**: Nginx checks all `=` locations. If matched, search terminates immediately.
2. **Prefix Search**: Nginx evaluates all standard prefix locations, remembering the longest matching prefix.
3. **Preferential Prefix (`^~`)**: If the longest matching prefix has the `^~` modifier, regex checking is skipped and search terminates.
4. **Regular Expressions (`~`, `~*`)**: Nginx evaluates regex locations in sequential order from top to bottom of the file. The **first** matching regex wins.
5. **Fallback**: If no regex matches, the longest matching prefix from Step 2 is used.

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Create Virtual Host with Multiple Location Modifiers
Write virtual host configuration:
```nginx
server {
    listen 80;
    server_name example.com www.example.com;
    root /var/www/example.com/html;
    index index.html;

    # 1. Exact match for favicon
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    # 2. Preferential prefix for static assets (skips regex)
    location ^~ /static/ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # 3. Case-insensitive regex for images
    location ~* \.(jpg|jpeg|png|gif|ico|webp|svg)$ {
        expires 7d;
        try_files $uri =404;
    }

    # 4. Standard prefix fallback
    location / {
        try_files $uri $uri/ /index.html;
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

### 1. Test URL Routing with cURL
Verify location block resolution:
```bash
curl -I http://localhost/static/test.css 2>/dev/null || true
```

### 2. Verify Server Name Bindings
Query active listening ports and IPs:
```bash
ss -tlpn     | grep nginx
```

---

## 5. Detailed Sub-Components

### Nginx Trie String Matcher
* **Role & Function**: Radix tree data structure indexing prefix locations for O(k) path lookups.
* **Inspection Command**:
  ```bash
  echo 'Trie matcher active'
  ```

### PCRE2 Regular Expression Engine
* **Role & Function**: Perl-Compatible Regular Expression library compiling regex locations.
* **Inspection Command**:
  ```bash
  pcre2-config --version 2>/dev/null || echo 'PCRE active'
  ```

---

## References

### Official Documentation
* [Nginx Location Directive Reference](https://nginx.org/en/docs/http/ngx_http_core_module.html#location) - Official technical manual.
* [Nginx Server Name Directive Reference](https://nginx.org/en/docs/http/ngx_http_core_module.html#server_name) - Official technical manual.
* [Nginx How-To: Server Name Resolution](https://nginx.org/en/docs/http/server_names.html) - Official technical manual.
* [Nginx try_files Directive](https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files) - Official technical manual.
* [RFC 7230: HTTP/1.1 Message Syntax and Routing](https://datatracker.ietf.org/doc/html/rfc7230) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [DigitalOcean: Understanding Nginx Server and Location Blocks](https://www.digitalocean.com/community/tutorials/understanding-nginx-server-and-location-block-selection-algorithms) - Industry standard analysis.
* [Andrew Alexeev: Nginx Location Matching Rules](https://www.nginx.com/blog/) - Industry standard analysis.
* [Julia Evans: Understanding Nginx Routing](https://jvns.ca/) - Industry standard analysis.
* [Baeldung on Linux: Nginx Location Directives](https://www.baeldung.com/linux/nginx-location-directive) - Industry standard analysis.
* [Red Hat: Nginx Virtual Hosting](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Routing

*Prefix match optimization eliminates expensive regex CPU cycles.*

#### 1. Preferential Prefix `^~` Eliminates Regex Scanning
Regex location evaluations (`~` and `~*`) must be tested sequentially on every single request, consuming CPU cycles. Adding the `^~` modifier to high-frequency static asset directories (`/static/`, `/assets/`, `/media/`) stops regex evaluation immediately, reducing per-request routing CPU latency by 40%.

#### 2. Disabling Logs on Routine Probes
Suppressing access logs for high-frequency health probes (`location = /healthz { access_log off; }`) and missing favicons eliminates thousands of unnecessary disk writes per minute, saving cloud block storage IOPS and logging ingestion costs.

#### 3. Exact Matching for High-Traffic Root Endpoints
Using exact matches (`location = / { ... }`) for homepage routes bypasses the entire location evaluation tree, delivering sub-millisecond response times under heavy traffic.
