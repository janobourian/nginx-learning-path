# Module 10: Stream Module — TCP/UDP Load Balancing

**Track:** Enterprise NGINX  
**Category:** Layer 4 Transport Proxying

---

## Beyond HTTP: The Stream Module

The `stream` module extends NGINX from an HTTP proxy to a **Layer 4 (TCP/UDP) proxy**. It operates below the HTTP protocol: instead of reading HTTP headers and routing based on URL, it opens a TCP or UDP connection and forwards raw bytes between the client and a backend server.

This makes it suitable for proxying protocols that NGINX has no built-in understanding of: MySQL, PostgreSQL, Redis, MongoDB, gRPC (over TCP), SMTP, DNS (over UDP), and any custom TCP-based protocol your application uses.

The stream module is separate from the `http` module and uses its own top-level context in `nginx.conf`.

---

## Basic TCP Load Balancing

```nginx
# nginx.conf
# The stream block is at the same level as http {}
# You cannot nest stream inside http {}

stream {
    # PostgreSQL cluster
    upstream postgres_cluster {
        server 10.0.0.1:5432;
        server 10.0.0.2:5432;
        server 10.0.0.3:5432;
    }

    server {
        listen 5432;
        proxy_pass postgres_cluster;

        # Timeout for establishing connection to backend
        proxy_connect_timeout 5s;

        # Timeout for data inactivity in either direction
        proxy_timeout 10m;   # Keep long-lived DB connections open
    }
}
```

With this configuration, applications connect to NGINX on port 5432 exactly as they would connect to PostgreSQL directly. NGINX forwards all bytes transparently. The application never knows it is talking through a proxy.

---

## Upstream Options in the Stream Module

```nginx
stream {
    upstream redis_cluster {
        # Least connections — route new connections to least busy backend
        least_conn;

        server 10.0.0.1:6379 weight=2 max_fails=3 fail_timeout=30s;
        server 10.0.0.2:6379 weight=2 max_fails=3 fail_timeout=30s;
        server 10.0.0.3:6379 weight=1 max_fails=3 fail_timeout=30s;
        server 10.0.0.4:6379 backup;

        # Keep idle connections to backends (avoids reconnect overhead)
        # stream keepalive works differently from http — it pools connections
    }

    server {
        listen 6379;
        proxy_pass redis_cluster;
        proxy_connect_timeout 2s;
        proxy_timeout 30m;
    }
}
```

---

## TLS Passthrough vs TLS Termination

The stream module can operate in two TLS modes:

### TLS Passthrough (Transparent)

NGINX forwards the raw TLS bytes to the backend without decrypting them. The backend terminates TLS. NGINX cannot inspect the content.

```nginx
stream {
    server {
        listen 443;
        # No ssl directives — just forward raw bytes
        proxy_pass backend_https;
        proxy_connect_timeout 5s;
        proxy_timeout 600s;
    }

    upstream backend_https {
        server 10.0.0.1:8443;
        server 10.0.0.2:8443;
    }
}
```

Use TLS passthrough when: the backend must handle the TLS session (for mutual TLS client authentication), you cannot share private keys with the NGINX server, or you need end-to-end encryption without NGINX seeing the payload.

### TLS Termination at NGINX (Stream with SSL)

NGINX decrypts the connection, forwards plain TCP to the backend.

```nginx
stream {
    server {
        listen 5433 ssl;

        ssl_certificate     /etc/ssl/certs/postgres.crt;
        ssl_certificate_key /etc/ssl/private/postgres.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_session_cache   shared:StreamSSL:5m;
        ssl_session_timeout 10m;

        proxy_pass postgres_internal;   # Backend on plain TCP
        proxy_connect_timeout 5s;
    }

    upstream postgres_internal {
        server 10.0.0.1:5432;   # Plain PostgreSQL, no TLS on internal network
        server 10.0.0.2:5432;
    }
}
```

This is useful when backends are inside a trusted network that does not need encryption, but external clients need encrypted connections.

---

## SNI-Based Routing (Multiple TLS Services on Port 443)

With SNI (Server Name Indication), NGINX can route different TLS connections to different backends based on the hostname the client announces in the TLS handshake — without decrypting the connection.

```nginx
stream {
    # Inspect the SNI hostname in the TLS ClientHello
    map $ssl_preread_server_name $backend_target {
        api.example.com     backend_api;
        db.example.com      backend_postgres;
        grpc.example.com    backend_grpc;
        default             backend_default;
    }

    upstream backend_api      { server 10.0.0.1:8443; }
    upstream backend_postgres  { server 10.0.0.2:5432; }
    upstream backend_grpc      { server 10.0.0.3:50051; }
    upstream backend_default   { server 10.0.0.4:8443; }

    server {
        listen 443;
        ssl_preread on;          # Read SNI without decrypting
        proxy_pass $backend_target;
        proxy_connect_timeout 5s;
    }
}
```

`ssl_preread on` activates the `$ssl_preread_server_name` variable by inspecting the TLS ClientHello extension — the initial unencrypted greeting the client sends that includes the desired hostname.

---

## UDP Load Balancing (DNS)

```nginx
stream {
    upstream dns_servers {
        server 8.8.8.8:53;
        server 8.8.4.4:53;
        server 1.1.1.1:53;
    }

    server {
        listen 53 udp;         # UDP keyword enables UDP mode
        proxy_pass dns_servers;
        proxy_timeout 5s;
        proxy_responses 1;     # DNS: expect exactly 1 UDP response per request
    }
}
```

UDP proxying does not maintain persistent connections. Each UDP datagram is forwarded independently. `proxy_responses` tells NGINX how many response packets to expect before considering the exchange complete.

---

## Combining `stream` and `http` in One NGINX

Both modules run in the same `nginx.conf`, but in separate top-level contexts:

```nginx
# /etc/nginx/nginx.conf

# Shared process settings
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 16384;
}

# HTTP proxying and web serving
http {
    include mime.types;
    include /etc/nginx/conf.d/*.conf;
}

# TCP/UDP proxying
stream {
    include /etc/nginx/stream.d/*.conf;
}
```

---

## Access Control and Logging in the Stream Module

```nginx
stream {
    # Define a log format for TCP connections
    log_format stream_log '$remote_addr [$time_local] '
                          '$protocol $status $bytes_sent $bytes_received '
                          '$session_time $upstream_addr';

    access_log /var/log/nginx/stream.log stream_log;

    server {
        listen 5432;

        # Allow connections only from application servers
        allow 10.0.0.0/16;
        deny  all;

        proxy_pass postgres_cluster;
    }
}
```

Stream access logging captures `$bytes_sent`, `$bytes_received`, and `$session_time` — useful for detecting database connection leaks (sessions open for hours without data transfer).

---

## CLI: Monitoring TCP Connections

```bash
# Check how many TCP connections are open to each backend
ss -tn dst 10.0.0.1:5432 | wc -l

# List all active stream proxy connections
ss -tn sport 5432 | awk '{print $5}' | sort | uniq -c

# Watch connection count to PostgreSQL backend in real time
watch -n 2 'ss -tn dst 10.0.0.1:5432 | wc -l'

# Reload stream configuration without interrupting existing connections
nginx -t && nginx -s reload

# Test raw TCP connectivity through NGINX to PostgreSQL
psql -h nginx_host -p 5432 -U myuser -d mydb -c "SELECT 1"

# Test that SNI routing works
openssl s_client -connect nginx_host:443 -servername api.example.com </dev/null 2>/dev/null | grep "subject="
openssl s_client -connect nginx_host:443 -servername grpc.example.com </dev/null 2>/dev/null | grep "subject="
```

---

## FinOps: Stream Module Eliminates Dedicated TCP Load Balancers

AWS NLB (Network Load Balancer) for TCP load balancing costs $0.008 per LCU-hour, with separate charges for processed bytes. A high-throughput database proxy through NLB handling 1 GB/hour costs approximately $100-200/month.

Using NGINX's stream module on existing compute instances for the same purpose eliminates the NLB cost entirely. For a startup with 5 database clusters each behind their own NLB, this saves approximately $500-1,000/month.

---

## Troubleshooting

**Stream proxying succeeds but application reports connection dropped after 60 seconds**

The default `proxy_timeout` is 10 minutes, but the OS kernel may close idle TCP connections sooner. Long-lived database connections benefit from TCP keepalive at the stream level:

```nginx
stream {
    server {
        listen 5432;
        proxy_pass postgres_cluster;
        proxy_timeout 1h;
        # Enable kernel TCP keepalive probes
        proxy_socket_keepalive on;
    }
}
```

**SNI-based routing sends all connections to `default` backend**

`ssl_preread on` must be set in the `server {}` block, and the mapping must use `$ssl_preread_server_name`, not `$host` (which is HTTP-layer). Verify the TLS client is sending SNI:

```bash
openssl s_client -connect nginx_host:443 -servername yourhost.com </dev/null 2>&1 | grep "SSL handshake"
```

If the client does not send SNI (old clients, some CLI tools), `$ssl_preread_server_name` is empty and the `default` route is used.
