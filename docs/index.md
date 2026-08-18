# Enterprise NGINX Architecture & Cloud Engineering — Master Index
**Repository:** `vit/nginx-learning-path`
**Domain:** High-Performance Reverse Proxy, API Gateway, Load Balancing & Cloud Architecture
**Target Certifications:** NGINX Certified Associate, CKA, AWS Advanced Networking Specialty, SRE Foundations
**Status:** ✅ Complete Production-Grade Reference

---

## 📌 Foundational Quick Notes (Original Notes)

* Common filesystem paths when running inside the `nginx` Docker container:
  * Default Web Root (`html`): `/usr/share/nginx/html`
  * Default Configuration Directory: `/etc/nginx/`
  * Virtual Hosts Directory: `/etc/nginx/conf.d/`

---

## 📚 Complete Enterprise NGINX Curriculum Index

| Module | Core Domain Covered | Target Certifications | Document Link |
| :--- | :--- | :--- | :--- |
| **00. Event-Driven Architecture** | Master/worker process model, non-blocking I/O multiplexing (`epoll`/`kqueue`) | NGINX, SRE | [`nginx_enterprise/00_nginx_architecture_event_driven_worker_model.md`](nginx_enterprise/00_nginx_architecture_event_driven_worker_model.md) |
| **01. Core Configuration Blocks** | Directive inheritance, `main`, `events`, `http`, `server`, `location` contexts | NGINX, SRE | [`nginx_enterprise/01_core_configuration_blocks_contexts_and_directives.md`](nginx_enterprise/01_core_configuration_blocks_contexts_and_directives.md) |
| **02. Virtual Hosts & Routing** | Server names, SNI, location modifier priority (`=`, `^~`, `~`, `~*`, prefix) | NGINX, DevOps | [`nginx_enterprise/02_http_server_virtual_hosts_and_location_matching.md`](nginx_enterprise/02_http_server_virtual_hosts_and_location_matching.md) |
| **03. Reverse Proxy & Keepalive** | `proxy_pass`, header forwarding (`X-Forwarded-For`), upstream keepalive pools | NGINX, SRE | [`nginx_enterprise/03_reverse_proxy_upstream_routing_and_keepalive.md`](nginx_enterprise/03_reverse_proxy_upstream_routing_and_keepalive.md) |
| **04. Load Balancing Algorithms** | Round robin, least conn, ip_hash, generic hash, backup nodes, failover | NGINX, AWS ANS | [`nginx_enterprise/04_load_balancing_algorithms_health_checks_and_session_persistence.md`](nginx_enterprise/04_load_balancing_algorithms_health_checks_and_session_persistence.md) |
| **05. Modern TLS & HTTP/3 QUIC** | TLS 1.3, OCSP stapling, session resumption, HTTP/2, HTTP/3 QUIC over UDP 443 | NGINX, CKS | [`nginx_enterprise/05_tls_ssl_certificates_ocsp_stapling_and_http2_http3_quic.md`](nginx_enterprise/05_tls_ssl_certificates_ocsp_stapling_and_http2_http3_quic.md) |
| **06. Caching & Microcaching** | `proxy_cache_path`, cache locking, stale fallback, 1-second microcaching | NGINX, SRE | [`nginx_enterprise/06_caching_mechanisms_cache_keys_purging_and_microcaching.md`](nginx_enterprise/06_caching_mechanisms_cache_keys_purging_and_microcaching.md) |
| **07. Rate Limiting & DDoS** | Leaky bucket rate limiting (`limit_req_zone`), burst buffers, nodelay | NGINX, Security | [`nginx_enterprise/07_rate_limiting_concurrency_controls_and_ddos_mitigation.md`](nginx_enterprise/07_rate_limiting_concurrency_controls_and_ddos_mitigation.md) |
| **08. Security Hardening & Headers** | HSTS, CSP, X-Frame-Options, CORS preflight handling, WAF integration | NGINX, CKS | [`nginx_enterprise/08_security_hardening_headers_cors_waf_and_naxsi.md`](nginx_enterprise/08_security_hardening_headers_cors_waf_and_naxsi.md) |
| **09. API Gateway Patterns** | `auth_request` token validation, JWT verification, microservice routing | NGINX, Cloud-Native | [`nginx_enterprise/09_api_gateway_patterns_jwt_validation_and_auth_request.md`](nginx_enterprise/09_api_gateway_patterns_jwt_validation_and_auth_request.md) |
| **10. Layer 4 TCP/UDP Streaming** | Stream module (`stream {}`), PostgreSQL/MySQL load balancing, UDP proxying | NGINX, AWS ANS | [`nginx_enterprise/10_stream_module_tcp_udp_load_balancing.md`](nginx_enterprise/10_stream_module_tcp_udp_load_balancing.md) |
| **11. Observability & Prometheus** | Structured JSON logging, timing variables, `stub_status`, Prometheus exporter | SRE, DevOps | [`nginx_enterprise/11_logging_metrics_prometheus_exporter_and_observability.md`](nginx_enterprise/11_logging_metrics_prometheus_exporter_and_observability.md) |
| **12. High Availability (Keepalived)** | VRRP heartbeat failover, floating Virtual IP (VIP), active-passive cluster | SRE, Linux | [`nginx_enterprise/12_high_availability_keepalived_vrrp_and_active_passive.md`](nginx_enterprise/12_high_availability_keepalived_vrrp_and_active_passive.md) |
| **13. Enterprise Master Blueprint** | Production-ready multi-tier microservice reverse proxy master template | All Tracks | [`nginx_enterprise/13_real_world_production_case_studies_and_enterprise_blueprints.md`](nginx_enterprise/13_real_world_production_case_studies_and_enterprise_blueprints.md) |

---

## 🛠️ Documentation Standards Applied Across All Guides
1. **👔 Executive Summary**: Non-technical explanation of business purpose, mechanics, and value for managers and teammates.
2. **Technical Deep Dives**: Comprehensive architecture explanations, event loops (`epoll`), and routing algorithms.
3. **Hands-On Step-by-Step Walkthroughs**: Reproducible labs for building, scaling, securing, and debugging NGINX.
4. **Clean, Escaped CLI Snippets**: Formatted with trailing ` \` line escapes, 4-space indentation, and zero in-code comments.
5. **Trustworthy Curated Sources**: Exactly 5 official documentation links + 5 authoritative engineering blogs per module.
6. **FinOps & Resource Governance**: 500+ word guidelines on keepalive pooling, microcaching, and cloud compute cost reduction.