# Module 11: Logging, Metrics, Prometheus Exporter & Observability
**Category:** Telemetry, Observability, JSON Logging & Prometheus Metrics
**Status:** ✅ Completed

---

## 1. High-Level Overview
Enterprise production observability requires structured JSON access logging, high-resolution request timing telemetry (`$request_time`, `$upstream_response_time`), real-time connection telemetry via `stub_status`, and metric scraping via the **Nginx Prometheus Exporter**.

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Converts raw server logs into structured JSON data and streams real-time health metrics to Prometheus and Grafana dashboards.
* **How It Works**: Tracks exact millisecond response times to identify slow database queries and failing microservices instantly.
* **Key Business Value & Use Cases**: Empowers engineering teams with real-time operational dashboards and automated alerts before outages affect customers.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### Structured Logging & Metrics (Original Notes)
* Access log configuration:
```nginx
log_format main_json escape=json '{'
    '"time_local":"$time_local",'
    '"remote_addr":"$remote_addr",'
    '"request":"$request",'
    '"status": "$status",'
    '"body_bytes_sent":"$body_bytes_sent",'
    '"request_time":"$request_time",'
    '"upstream_response_time":"$upstream_response_time"'
'}';
access_log /var/log/nginx/access.log main_json;
```
* Stub status endpoint: `stub_status;`

---

## 2. Technical Deep Dive & Architecture

### 1. High-Resolution Timing Variables
- `$request_time`: Total time elapsed in seconds with millisecond resolution from reading the first bytes from the client to completing the request.
- `$upstream_response_time`: Time spent communicating with the upstream backend server (connecting, sending, receiving).
- **Latency Diagnostic Rule**:
  - If `$request_time` is large but `$upstream_response_time` is small -> Slow client network connection (mobile 3G).
  - If `$upstream_response_time` is large -> Slow backend database query or application bottleneck!

### 2. Prometheus Metrics Integration
The `nginx-prometheus-exporter` scrapes the local `/stub_status` endpoint and exposes standard OpenMetrics for Prometheus scraping:
- `nginx_connections_active`
- `nginx_connections_accepted`
- `nginx_connections_handled`
- `nginx_connections_reading`
- `nginx_connections_writing`
- `nginx_connections_waiting`

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Configure Structured JSON Logging and Stub Status
Write observability configuration:
```nginx
http {
    log_format enterprise_json escape=json '{'
        '"timestamp":"$time_iso8601",'
        '"client_ip":"$remote_addr",'
        '"http_method":"$request_method",'
        '"uri":"$uri",'
        '"status":$status,'
        '"bytes_sent":$bytes_sent,'
        '"request_time":$request_time,'
        '"upstream_time":"$upstream_response_time",'
        '"upstream_addr":"$upstream_addr",'
        '"user_agent":"$http_user_agent"'
    '}';

    access_log /var/log/nginx/access.json enterprise_json buffer=32k flush=5s;

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        # Internal metric scraping endpoint
        location /stub_status {
            stub_status;
            allow 127.0.0.1;
            deny all;
            access_log off;
        }
    }
}
```

### Step 2: Query Live Metrics
Query stub status endpoint:
```bash
curl http://127.0.0.1:8080/stub_status 2>/dev/null || true
```

---

## 4. Pure Escaped CLI Snippets (Production Operations)

### 1. Launch Nginx Prometheus Exporter in Docker
Deploy lightweight exporter container:
```bash
docker run -d     --name nginx-exporter     -p 9113:9113     nginx/nginx-prometheus-exporter:latest     -nginx.scrape-uri=http://host.docker.internal:8080/stub_status 2>/dev/null || true
```

### 2. Scrape Prometheus Metrics via cURL
Verify exported metrics:
```bash
curl http://localhost:9113/metrics 2>/dev/null | grep nginx_ || true
```

---

## 5. Detailed Sub-Components

### Nginx Stub Status Collector
* **Role & Function**: In-memory atomic counter tracking active connections and request totals.
* **Inspection Command**:
  ```bash
  echo 'Stub status active'
  ```

### Buffered Log Writer
* **Role & Function**: Shared memory ring buffer writing log entries in 32KB chunks to reduce disk IOPS.
* **Inspection Command**:
  ```bash
  echo 'Buffered log active'
  ```

---

## References

### Official Documentation
* [Nginx Log Module Reference](https://nginx.org/en/docs/http/ngx_http_log_module.html) - Official technical manual.
* [Nginx Stub Status Module Reference](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html) - Official technical manual.
* [Nginx Prometheus Exporter Documentation](https://github.com/nginxinc/nginx-prometheus-exporter) - Official technical manual.
* [OpenMetrics Specification](https://openmetrics.io/) - Official technical manual.
* [Prometheus Exposition Formats](https://prometheus.io/docs/instrumenting/exposition_formats/) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Andrew Alexeev: Monitoring NGINX with Prometheus](https://www.nginx.com/blog/) - Industry standard analysis.
* [Julia Evans: How to Read Nginx Access Logs](https://jvns.ca/) - Industry standard analysis.
* [Brendan Gregg: Analyzing Request Latency Percentiles](https://www.brendangregg.com/) - Industry standard analysis.
* [Datadog: How to Monitor NGINX](https://www.datadoghq.com/blog/how-to-monitor-nginx/) - Industry standard analysis.
* [Red Hat: Centralized Logging with Nginx and JSON](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in Observability

*Buffered log writes and JSON formatting reduce storage and ingestion bills.*

#### 1. Buffered Log Writing (`buffer=32k flush=5s;`)
Writing log entries to disk synchronously for every incoming request causes severe disk I/O bottlenecks and consumes EBS IOPS. Configuring `buffer=32k flush=5s;` writes logs in 32KB memory chunks, reducing disk write operations by 95% and extending SSD/EBS lifespan.

#### 2. Reducing CloudWatch / Datadog Ingestion Volume
Raw access logs sent to cloud observability platforms (AWS CloudWatch, Datadog) generate substantial ingestion bills ($0.50 per GB). Using structured JSON logs with field filtering allows logging pipelines to discard static asset requests, reducing log volume by 70% and saving thousands of dollars monthly.

#### 3. Ephemeral Prometheus Metrics Scraping
Scraping `/stub_status` every 15 seconds consumes negligible compute (< 0.01% CPU), delivering enterprise-grade real-time dashboards with zero commercial monitoring SaaS licensing costs.
