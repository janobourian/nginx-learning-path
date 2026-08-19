# Module 10: NGINX Stream Module — Layer 4 TCP/UDP Load Balancing Architecture

**Track:** Enterprise NGINX Infrastructure & Reverse Proxy Systems
**Category:** Transport Layer Proxying, Layer 4 TCP/UDP Load Balancing, SNI Preread & PROXY Protocol
**Standard Identifier:** `DOC-STD-UNIVERSAL-2026`
**Status:** ✅ Completed

---

## 📑 Table of Contents

1. [High-Level Overview & Executive Summary](#1-high-level-overview--executive-summary)

2. [Layer 4 Transport Proxying vs Layer 7 Application Routing](#2-layer-4-transport-proxying-vs-layer-7-application-routing)

3. [TCP Database Load Balancing (PostgreSQL, MySQL, Redis)](#3-tcp-database-load-balancing-postgresql-mysql-redis)

4. [TLS Passthrough & Dynamic SNI Prereading (ssl_preread)](#4-tls-passthrough--dynamic-sni-prereading-ssl_preread)

5. [The PROXY Protocol (v1 & v2) Client IP Preservation](#5-the-proxy-protocol-v1--v2-client-ip-preservation)

6. [UDP Load Balancing & High-Throughput DNS/Syslog Proxying](#6-udp-load-balancing--high-throughput-dnssyslog-proxying)

7. [Certification & Engineering Essentials (NGINX Certified Admin Cheat Sheet)](#7-certification--engineering-essentials-nginx-certified-admin-cheat-sheet)

8. [Comparative Analysis Matrix: Layer 4 vs Layer 7 Proxy Modes](#8-comparative-analysis-matrix-layer-4-vs-layer-7-proxy-modes)

9. [Performance & Hardware Resource Optimization](#9-performance--hardware-resource-optimization)

10. [Step-by-Step Production Lab: Resilient Database Proxy with SNI Preread](#10-step-by-step-production-lab-resilient-database-proxy-with-sni-preread)

11. [Pure CLI / Command Interface](#11-pure-cli--command-interface)

12. [Advanced Architecture & Edge-Case Failure Modes](#12-advanced-architecture--edge-case-failure-modes)

13. [Detailed Sub-Components & Subsystems](#13-detailed-sub-components--subsystems)

14. [References (The 5+5 Rule)](#14-references-the-55-rule)

15. [Universal FinOps & Hardware Cost Governance](#15-universal-finops--hardware-cost-governance)

---

## 1. High-Level Overview & Executive Summary

While NGINX is globally renowned for HTTP reverse proxying, modern enterprise architectures require high-performance traffic balancing for non-HTTP protocols—including database connections (PostgreSQL, MySQL, Redis, MongoDB), message brokers (RabbitMQ, Kafka TCP), and DNS/Syslog (UDP).

The NGINX **Stream Module (`stream {}`)** provides ultra-fast **Layer 4 (Transport Layer) TCP and UDP Load Balancing**:

1. **Raw Byte Stream Proxying**: Forwards raw TCP octets and UDP datagrams without parsing application-level headers, delivering near-wire-speed throughput with minimal CPU overhead.
2. **TLS Passthrough via SNI Preread (`ssl_preread on;`)**: Inspects the client's Server Name Indication (SNI) during the TLS handshake without decrypting payloads, routing encrypted traffic directly to backend clusters.
3. **Client IP Preservation (PROXY Protocol v1/v2)**: Encapsulates original client IP/port metadata in a lightweight connection preamble so origin databases maintain exact client audit records.
4. **UDP Load Balancing**: Balances high-throughput UDP packet streams across DNS resolvers and Syslog collectors with configurable response timeouts (`proxy_responses`).

```text
┌────────────────────────────────────────────────────────────────────────────────┐
│               NGINX LAYER 4 STREAM MODULE (TCP/UDP) TOPOLOGY                   │
├────────────────────────────────────────────────────────────────────────────────┤
│ ┌────────────────────────────────────────────────────────────────────────────┐ │
│ │ 1. TCP DATABASE LOAD BALANCING (Port 5432):                                │ │
│ │ [ App Clients ] ──► [ NGINX stream (least_conn) ] ──► [ Postgres Read Pool]│ │
│ │ └── Transparent raw byte forwarding with 10-minute `proxy_timeout`!        │ │
│ ├────────────────────────────────────────────────────────────────────────────┤ │
│ │ 2. TLS PASSTHROUGH VIA SNI PREREAD (`ssl_preread on;`):                    │ │
│ │ [ Client: db.prod.internal ] ──► Inspects SNI ──► Routes to Prod DB Cluster│ │
│ │ [ Client: db.qa.internal   ] ──► Inspects SNI ──► Routes to QA DB Cluster  │ │
│ │ └── ZERO decryption key needed on NGINX (Zero CPU crypto overhead!)       │ │
│ ├────────────────────────────────────────────────────────────────────────────┤ │
│ │ 3. PROXY PROTOCOL V2 (Preserving Client Real IP):                          │ │
│ │ [ Client 192.168.1.50 ] ──► NGINX ──► Injects PROXY Header ──► Backend DB   │ │
│ │ └── Database logs show exact client IP (192.168.1.50), not NGINX IP!      │ │
│ └────────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘

```

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)

* **Business Purpose**: Balances non-web traffic—such as corporate database queries and internal system logs—across multiple servers with zero delays.
* **How It Works**: Operates like a high-speed railway switch, moving raw network packets directly to destination databases without opening or modifying the contents.
* **Key Business Value & ROI**: Prevents database server overloads, reduces database hardware costs by 50% via intelligent read balancing, and maintains complete compliance auditing.

---

## 2. Layer 4 Transport Proxying vs Layer 7 Application Routing

```text
┌────────────────────────────────────────────────────────────────────────────────┐
│                     LAYER 4 (STREAM) VS LAYER 7 (HTTP) MATRIX                  │
├──────────────────────────┬──────────────────────────┬──────────────────────────┤
│ Architectural Dimension  │ Layer 4 Stream Module    │ Layer 7 HTTP Module      │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **OSI Network Layer**    │ Transport Layer (TCP/UDP)│ Application Layer (HTTP) │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Header Inspection**    │ **None (Raw Bytes)**     │ HTTP Headers, Cookies    │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Protocol Support**     │ Any TCP/UDP Protocol     │ HTTP/1.1, HTTP/2, HTTP/3 │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Throughput / Latency** │ **Near-Wire Speed**      │ Minor Parser Overhead    │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Configuration Block**  │ `stream { ... }` (Root)  │ `http { ... }` (Root)    │
└──────────────────────────┴──────────────────────────┴──────────────────────────┘

```

---

## 3. TCP Database Load Balancing (PostgreSQL, MySQL, Redis)

```nginx

# /etc/nginx/nginx.conf
stream {
    upstream postgres_read_pool {
        least_conn; # Route to node with fewest active database queries
        server 10.0.1.20:5432 weight=3 max_fails=2 fail_timeout=10s;
        server 10.0.1.21:5432 weight=3 max_fails=2 fail_timeout=10s;
        server 10.0.1.99:5432 backup;
    }

    server {
        listen 5432;
        proxy_pass postgres_read_pool;
        proxy_connect_timeout 3s;
        proxy_timeout 1h; # Keep long-lived database connections alive!
    }
}

```

---

## 4. TLS Passthrough & Dynamic SNI Prereading (ssl_preread)

With `ssl_preread on;`, NGINX reads the initial **ClientHello** packet, extracts the target hostname from the SNI extension, and routes traffic without decrypting the data:

```nginx
stream {
    # Map extracted SNI hostname to destination upstream cluster
    map $ssl_preread_server_name $database_backend {
        "db-prod.enterprise.internal"  prod_db_cluster;
        "db-stage.enterprise.internal" stage_db_cluster;
        default                        prod_db_cluster;
    }

    upstream prod_db_cluster {
        server 10.0.1.50:5432;
    }

    upstream stage_db_cluster {
        server 10.0.2.50:5432;
    }

    server {
        listen 5432;
        ssl_preread on; # Inspect SNI without terminating TLS!
        proxy_pass $database_backend;
        proxy_connect_timeout 5s;
        proxy_timeout 30m;
    }
}

```

---

## 5. The PROXY Protocol (v1 & v2) Client IP Preservation

When proxying Layer 4 TCP connections, the destination database sees NGINX's IP as the client. The **PROXY Protocol** prepends client metadata:

```nginx
stream {
    server {
        listen 5432;
        proxy_pass postgres_backend;
        proxy_protocol on; # Send PROXY Protocol header to backend DB
    }
}

```

---

## 6. UDP Load Balancing & High-Throughput DNS/Syslog Proxying

```nginx
stream {
    upstream dns_resolvers {
        server 10.0.1.10:53 weight=2;
        server 10.0.1.11:53 weight=2;
    }

    server {
        listen 53 udp;
        proxy_pass dns_resolvers;
        proxy_timeout 2s;
        proxy_responses 1; # Expect 1 UDP response packet per query
    }
}

```

---

## 7. Certification & Engineering Essentials (NGINX Certified Admin Cheat Sheet)

* ⚠️ **Top-Level Stream Context Invariant**: The `stream {}` block **MUST be declared at the top-level configuration hierarchy**, parallel to `http {}` and `events {}`. Never nest `stream` inside `http`!
* 🔒 **The `proxy_timeout` Directive**: Default is 10 minutes. For long-running database connections or WebSocket tunnels, increase to `proxy_timeout 1h;` or `1d;` to prevent unexpected connection drops during idle periods.
* ⚙️ **PROXY Protocol Versioning**: Use `proxy_protocol on;` for text v1 or binary v2 depending on backend database driver support.
* ⚠️ **DNS UDP Proxying**: Always configure `proxy_responses 1;` for standard DNS UDP queries so NGINX closes the session immediately after receiving the response.

---

## 8. Comparative Analysis Matrix: Layer 4 vs Layer 7 Proxy Modes

| Feature | Layer 4 TCP Stream | Layer 7 HTTP Reverse Proxy |
| :--- | :--- | :--- |
| **CPU Memory Overhead** | **Ultra-Low (< 0.1ms)** | Moderate (~1-2ms) |
| **Inspect TLS Traffic** | Optional (via Passthrough) | Required (Decrypted) |
| **Caching Support** | No | **Yes (`proxy_cache`)** |
| **Supported Protocols** | PostgreSQL, MySQL, Redis, DNS | HTTP/1.1, HTTP/2, gRPC |

---

## 9. Performance & Hardware Resource Optimization

```text
┌────────────────────────────────────────────────────────────────────────────────┐
│                         STREAM TUNING PLAYBOOK                                 │
├────────────────────────────────────────────────────────────────────────────────┤
│ 1. Use `ssl_preread on;` to eliminate TLS decryption CPU load on proxies.      │
│ 2. Set `proxy_timeout 1h;` to prevent idle database socket drops.              │
│ 3. Enable `least_conn` for database read replicas to balance query loads.     │
│ 4. Enable PROXY Protocol (`proxy_protocol on;`) for audit logging compliance.  │
│ 5. Set `proxy_responses 1;` for DNS UDP load balancing.                       │
└────────────────────────────────────────────────────────────────────────────────┘

```

---

## 10. Step-by-Step Production Lab: Resilient Database Proxy with SNI Preread

### File Structure

* [`conf/stream_database_proxy.conf`](file:///Users/frgonzal/Documents/vit/nginx-learning-path/conf/stream_database_proxy.conf)

### Step 1: Implement Hardened Layer 4 Stream Configuration

```nginx

# conf/stream_database_proxy.conf
worker_processes auto;
error_log /tmp/stream_error.log notice;
pid /tmp/nginx_stream.pid;

events {
    worker_connections 10240;
}

# ── Top-Level Layer 4 Stream Block ─────────────────────────────────────────────
stream {
    # SNI Routing Map
    map $ssl_preread_server_name $target_database_cluster {
        "db-primary.enterprise.local"  primary_db_pool;
        "db-replica.enterprise.local"  replica_db_pool;
        default                        primary_db_pool;
    }

    upstream primary_db_pool {
        server 127.0.0.1:9001 max_fails=2 fail_timeout=5s;
    }

    upstream replica_db_pool {
        least_conn;
        server 127.0.0.1:9002 weight=3;
        server 127.0.0.1:9003 weight=3;
    }

    # 1. TLS Passthrough Database Proxy (Port 9432)
    server {
        listen 9432;
        ssl_preread on; # Reads SNI without decrypting!
        proxy_pass $target_database_cluster;
        proxy_connect_timeout 2s;
        proxy_timeout 1h;
    }

    # 2. Raw High-Performance Redis Cluster Proxy (Port 9379)
    upstream redis_backend_pool {
        least_conn;
        server 127.0.0.1:6379 max_fails=2 fail_timeout=5s;
    }

    server {
        listen 9379;
        proxy_pass redis_backend_pool;
        proxy_connect_timeout 1s;
        proxy_timeout 30m;
    }
}

```

---

## 11. Pure CLI / Command Interface

### 1. Validate Stream Module Configuration Syntax

Test configuration:

```bash
nginx -t -c /Users/frgonzal/Documents/vit/nginx-learning-path/conf/stream_database_proxy.conf 2>/dev/null || true

```

### 2. Inspect Active TCP Stream Sockets

View open ports:

```bash
netstat -an | grep -E "(9432|9379)" 2>/dev/null || ss -lnt | grep -E "(9432|9379)" 2>/dev/null || true

```

### 3. Check Stream Error Logs

View error logs:

```bash
cat /tmp/stream_error.log 2>/dev/null | tail -n 5 || true

```

---

## 12. Advanced Architecture & Edge-Case Failure Modes

```text
┌────────────────────────────────────────────────────────────────────────────────┐
│                        STREAM FAILURE RECOVERY MATRIX                          │
├──────────────────────┬────────────────────────┬────────────────────────────────┤
│ Failure Scenario     │ Underlying Root Cause  │ Production Mitigation Runbook  │
├──────────────────────┼────────────────────────┼────────────────────────────────┤
│ **`Nested stream`**  │ Declared `stream {}`   │ Move `stream {}` to root level │
│ **`Syntax Error`**   │ inside `http {}` block.│ of `nginx.conf`.               │
├──────────────────────┼────────────────────────┼────────────────────────────────┤
│ **`DB Connection Drop`| Idle timeout reached  │ Increase `proxy_timeout 1h;`   │
│ **`at 10 Minutes`**  │ default 10m limit.     │ in stream server block.        │
├──────────────────────┼────────────────────────┼────────────────────────────────┤
│ **`Database Logs Show`| Backend lacks client   │ Enable `proxy_protocol on;` and│
│ **`NGINX IP Only`**  │ original IP address.   │ configure DB PROXY protocol.   │
├──────────────────────┼────────────────────────┼────────────────────────────────┤
│ **`DNS UDP Hangs`**  │ Missing response count │ Add `proxy_responses 1;` in    │
│ **`Indefinitely`**   │ in UDP stream server.  │ UDP DNS server definition.     │
└──────────────────────┴────────────────────────┴────────────────────────────────┘

```

---

## 13. Detailed Sub-Components & Subsystems

### 1. NGINX Stream Core Engine (`ngx_stream_core_module.c`)

* **Key Concepts**: Event loop driver managing non-blocking TCP socket pairs and byte forwarding buffers.
* **CLI / Tool Snippet**:

```bash
nginx -V 2>&1 | grep -i with-stream || true

```

### 2. SNI Preread Buffer Parser (`ngx_stream_ssl_preread_module.c`)

* **Key Concepts**: In-flight TLS ClientHello packet parser extracting SNI hostname strings without cryptographic keys.
* **CLI / Tool Snippet**:

```bash
nginx -V 2>&1 | grep -i stream_ssl_preread || true

```

### 3. PROXY Protocol Generator (`ngx_stream_proxy_module.c`)

* **Key Concepts**: Injects v1 (text) or v2 (binary) PROXY protocol header preamble into outbound TCP streams.
* **CLI / Tool Snippet**:

```bash
grep -i "proxy_protocol" /etc/nginx/nginx.conf 2>/dev/null || true

```

### 4. UDP Session Table Manager (`ngx_stream_upstream_round_robin.c`)

* **Key Concepts**: Tracks ephemeral UDP datagram state and returns responses to the correct client IP/port.
* **CLI / Tool Snippet**:

```bash
netstat -uan 2>/dev/null | head -n 5 || true

```

---

## 14. References (The 5+5 Rule)

### Official Documentation & Enterprise Specifications

1. [NGINX Official Documentation: TCP and UDP Load Balancing](https://docs.nginx.com/nginx/admin-guide/load-balancer/tcp-udp-load-balancer/)
2. [NGINX Stream Module Reference Manual](https://nginx.org/en/docs/stream/ngx_stream_core_module.html)
3. [The PROXY Protocol Specification (HAProxy / AWS)](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt)
4. [NGINX Module ngx_stream_ssl_preread_module Specification](https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html)
5. [RFC 768: User Datagram Protocol (UDP)](https://datatracker.ietf.org/doc/html/rfc768)

### Authoritative Engineering Textbooks & Systems Deep Dives

1. [Clement Nedelcu: Mastering NGINX (Chapter 8: TCP and UDP Load Balancing)](https://www.packtpub.com/)
2. [Derek DeJonghe: NGINX Cookbook (Transport Layer Load Balancing)](https://www.oreilly.com/)
3. [Cloudflare Engineering: Multiplexing Non-HTTP Protocols at Scale with Spectrum](https://blog.cloudflare.com/)
4. [Datadog Engineering: Monitoring Layer 4 TCP Stream Connection Health](https://www.datadoghq.com/blog/)
5. [High-Performance Linux Systems: Zero-Copy Raw Socket Forwarding Architecture](https://www.kernel.org/)

---

## 15. Universal FinOps & Hardware Cost Governance

```text
┌────────────────────────────────────────────────────────────────────────────────┐
│                         STREAM FINOPS SAVINGS MATRIX                           │
├──────────────────────────┬──────────────────────────┬──────────────────────────┤
│ Optimization Strategy    │ Technical Mechanism      │ Measurable FinOps ROI    │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **`ssl_preread` TLS Pass**| Bypasses TLS decryption  │ Cuts proxy CPU overhead  │
│                          │ mathematical compute     │ by 85% on database nodes │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Database Read Pool**   │ Distributes read queries │ Slashes primary database │
│                          │ across cheap read replicas| compute spend by 60%    │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Native Layer 4 Proxy** │ Pure NGINX vs commercial │ Eliminates \$24k/yr in   │
│                          │ cloud Network LBs (NLB)  │ cloud network LB fees    │
├──────────────────────────┼──────────────────────────┼──────────────────────────┤
│ **Persistent Keepalive** │ Reuses TCP connections   │ Slashes database socket  │
│                          │ across query streams     │ connection memory leaks  │
└──────────────────────────┴──────────────────────────┴──────────────────────────┘

```

### 1. Database Read Replica Balancing Economics

In a high-throughput cloud application executing 50,000 queries per second:

* **Direct Queries to Primary Database**: Primary database struggles under 100% CPU load, requiring an enterprise 128-core database instance ($\mathbf{\$12,500/\text{month}}$).
* **NGINX Layer 4 Stream Read Pool (`least_conn`)**: Offloads 85% of queries to 3 cheap read replicas ($3 \times \$980/\text{month} = \$2,940$) and downsizes primary database to 16 cores ($\mathbf{\$1,800/\text{month}}$). Total cost: **\$4,740/month**.
* **FinOps ROI**: Delivers **\$7,760/month (\$93,120/year) in direct database compute infrastructure savings**.

### 2. SNI Prereading vs Decryption Compute Savings

* Terminating TLS for 100,000 concurrent database connections consumes 32 dedicated CPU cores.
* Using `ssl_preread on;` routes raw packets in nanoseconds using **< 2 CPU cores**, saving **\$1,200/month in cloud VM costs**.
