# Module 11: Logging, Metrics, Prometheus Exporter & Observability

**Track:** Enterprise NGINX  
**Category:** Operational Visibility & Monitoring

---

## Why NGINX Observability Matters

NGINX sits at the edge of your infrastructure, seeing every request before it reaches your application. The data it collects — latency, status codes, upstream response times, connection counts — is the most accurate picture of what your users are actually experiencing. Without proper logging and metrics, production incidents become guesswork.

Observability for NGINX has three pillars: **logs** (what happened, request by request), **metrics** (aggregated counts and durations over time), and **traces** (end-to-end request flow across services). This module covers all three.

---

## Structured Access Logging

The default NGINX log format is human-readable but hard to parse programmatically. For production systems, switch to **JSON logging** so logs can be ingested directly by Elasticsearch, Loki, or Datadog without regex parsing.

```nginx
http {
    log_format json_combined escape=json
        '{'
        '"time":"$time_iso8601",'
        '"remote_addr":"$remote_addr",'
        '"method":"$request_method",'
        '"uri":"$uri",'
        '"args":"$args",'
        '"status":$status,'
        '"bytes_sent":$body_bytes_sent,'
        '"request_time":$request_time,'
        '"upstream_addr":"$upstream_addr",'
        '"upstream_status":"$upstream_status",'
        '"upstream_response_time":"$upstream_response_time",'
        '"upstream_connect_time":"$upstream_connect_time",'
        '"http_referrer":"$http_referer",'
        '"http_user_agent":"$http_user_agent",'
        '"http_x_forwarded_for":"$http_x_forwarded_for",'
        '"request_id":"$request_id",'
        '"ssl_protocol":"$ssl_protocol",'
        '"ssl_cipher":"$ssl_cipher",'
        '"cache_status":"$upstream_cache_status"'
        '}';

    access_log /var/log/nginx/access.json json_combined;
    error_log  /var/log/nginx/error.log warn;
}
```

The `escape=json` parameter (NGINX 1.11.8+) automatically escapes special characters in variable values so the output is always valid JSON.

---

## Conditional Logging: Reducing Log Volume

Logging every request including static asset fetches creates enormous log volumes with low diagnostic value. Use conditional logging to exclude noise:

```nginx
http {
    log_format json_combined escape=json '{ ... }';

    # Map: 1 = suppress this request from logs
    map $request_uri $loggable {
        default              1;
        "~*\.(ico|css|js|gif|jpg|jpeg|png|svg|woff2|woff|ttf)$"  0;
        "/health"            0;
        "/metrics"           0;
        "/favicon.ico"       0;
    }

    server {
        access_log /var/log/nginx/access.json json_combined if=$loggable;
    }
}
```

This typically reduces log volume by 40-70% while preserving all application request records.

---

## The `stub_status` Module: Built-in Metrics Endpoint

NGINX ships with a minimal metrics endpoint called `stub_status`:

```nginx
server {
    listen 127.0.0.1:8080;

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny  all;
        access_log off;
    }
}
```

```bash
curl http://127.0.0.1:8080/nginx_status
```

Output:
```
Active connections: 1247
server accepts handled requests
 45823419 45823419 89231088
Reading: 12 Writing: 89 Waiting: 1146
```

| Field | Meaning |
|---|---|
| `Active connections` | Total currently open client connections |
| `accepts` | Total connections accepted since startup |
| `handled` | Total connections handled (same as accepts unless drops occurred) |
| `requests` | Total HTTP requests served |
| `Reading` | Workers reading request headers |
| `Writing` | Workers sending responses |
| `Waiting` | Idle keepalive connections |

---

## Prometheus Metrics with `nginx-prometheus-exporter`

For time-series monitoring with Prometheus and Grafana, use the official `nginx-prometheus-exporter` sidecar. It scrapes `stub_status` and exposes metrics in Prometheus format.

```bash
# Run as a Docker container alongside NGINX
docker run -p 9113:9113 \
    nginx/nginx-prometheus-exporter:latest \
    --nginx.scrape-uri=http://localhost:8080/nginx_status
```

Metrics exposed at `http://localhost:9113/metrics`:

```
# HELP nginx_connections_active Active client connections
nginx_connections_active 1247

# HELP nginx_connections_accepted Total accepted connections
nginx_connections_accepted 45823419

# HELP nginx_http_requests_total Total HTTP requests
nginx_http_requests_total 89231088

# HELP nginx_connections_reading Connections reading request
nginx_connections_reading 12

# HELP nginx_connections_writing Connections writing response
nginx_connections_writing 89

# HELP nginx_connections_waiting Idle keepalive connections
nginx_connections_waiting 1146
```

Prometheus scrape configuration:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-host:9113']
    scrape_interval: 15s
```

---

## Custom Request Metrics via Access Log Parsing

When `stub_status` is insufficient, derive richer metrics from access logs using tools like **GoAccess** (real-time), **Vector** (log pipeline), or **Promtail + Loki** (log aggregation):

```bash
# GoAccess: real-time terminal dashboard from JSON access logs
goaccess /var/log/nginx/access.json \
    --log-format='{"time":"%dT%t%^","remote_addr":"%h","method":"%m","uri":"%U","status":%s,"bytes_sent":%b,"request_time":%T}' \
    --date-format='%Y-%m-%d' \
    --time-format='%H:%M:%S' \
    -o /var/www/html/report.html \
    --real-time-html

# Extract p99 request latency from JSON access log
jq -r '.request_time' /var/log/nginx/access.json \
    | sort -n \
    | awk 'BEGIN{c=0} {a[c++]=$1} END{print "p50:", a[int(c*0.50)], "p99:", a[int(c*0.99)]}'

# Status code distribution
jq -r '.status' /var/log/nginx/access.json \
    | sort | uniq -c | sort -rn
```

---

## Correlating NGINX Logs with Upstream Traces (Request ID Propagation)

For distributed tracing, generate a unique request ID at NGINX and propagate it through to all backend services:

```nginx
http {
    # Generate unique request ID if not already set by a load balancer
    map $http_x_request_id $request_id_value {
        ""      $request_id;         # NGINX-generated UUID (requires NGINX 1.11.0+)
        default $http_x_request_id;  # Use existing if passed by upstream LB
    }

    log_format json_combined escape=json
        '{"request_id":"$request_id_value","uri":"$uri", ... }';

    server {
        location /api/ {
            # Forward request ID to backend so it appears in backend logs too
            proxy_set_header X-Request-Id $request_id_value;

            # Return it to the client so they can report it in support tickets
            add_header X-Request-Id $request_id_value always;

            proxy_pass http://backend;
        }
    }
}
```

When a user reports an error, they provide the `X-Request-Id`. You search that ID in both NGINX logs and backend logs to get the complete request trace without a full distributed tracing system.

---

## Log Rotation

NGINX keeps log files open via file descriptors. Rotating logs requires telling NGINX to reopen them after the rotation tool (logrotate) renames the old file:

```
# /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        # Signal NGINX to reopen log files
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 $(cat /var/run/nginx.pid)
        fi
    endscript
}
```

The `USR1` signal (`nginx -s reopen`) closes and reopens all log files, allowing the rotation tool to compress and archive the old file.

---

## CLI Quick Reference

```bash
# Live request stream with status code highlighting
tail -f /var/log/nginx/access.json | jq -r '"\(.status) \(.method) \(.uri) \(.request_time)s"'

# Count requests per endpoint in last hour
grep "$(date -d '1 hour ago' '+%Y-%m-%dT%H')" /var/log/nginx/access.json \
    | jq -r '.uri' | sort | uniq -c | sort -rn | head -20

# Find slowest requests (over 5 seconds)
jq -r 'select(.request_time > 5) | "\(.request_time)s \(.method) \(.uri)"' \
    /var/log/nginx/access.json | sort -rn | head -20

# Error rate over last 5 minutes
grep "$(date '+%Y-%m-%dT%H:%M')" /var/log/nginx/access.json \
    | jq -r '.status' \
    | awk '$1 >= 500 {err++} {total++} END {printf "%.2f%%\n", err/total*100}'

# Send NGINX access logs to syslog instead of file
# In nginx.conf: access_log syslog:server=127.0.0.1:514,tag=nginx json_combined;
```

---

## FinOps: Observability ROI

The NGINX access log is the single most valuable dataset for optimizing infrastructure costs. By analyzing `$upstream_response_time` you identify which endpoints are slow and need caching or backend optimization. By analyzing `$bytes_sent` per endpoint you identify candidates for response compression or smaller payload design. These insights enable targeted optimizations that reduce backend instance counts and CDN egress fees — typically a 20-40% infrastructure cost reduction when acted on systematically.

---

## Troubleshooting

**Log file not updated despite requests being served**

NGINX may have lost its file descriptor after a log rotation. Run `nginx -s reopen` or `kill -USR1 $(cat /var/run/nginx.pid)`.

**JSON logs contain unescaped quotes breaking parsers**

Ensure `escape=json` is specified in the `log_format` directive. Without it, values containing `"` or `\n` will produce invalid JSON.

**`$request_id` is empty or static**

`$request_id` requires NGINX 1.11.0 or later. Verify with `nginx -v`. On older versions, generate a random value via a Lua snippet or use a UUID header set by the upstream load balancer.
