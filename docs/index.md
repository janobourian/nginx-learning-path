# Enterprise Software Architecture & Web Engineering — Master Curriculum Index
**Repository:** `vit/nginx-learning-path`
**Domain:** High-Performance Web Servers, Cloud Gateways, Full-Stack JavaScript/TypeScript & Cross-Platform Mobile/Web (Dart/Flutter)
**Status:** ✅ Complete Production-Grade Reference

---

## 📌 Foundational Quick Notes (Original Notes)

* Common filesystem paths when running inside the `nginx` Docker container:
  * Default Web Root (`html`): `/usr/share/nginx/html`
  * Default Configuration Directory: `/etc/nginx/`
  * Virtual Hosts Directory: `/etc/nginx/conf.d/`

---

## 🌐 Full-Stack Web Development & Cross-Platform Technology Curriculum

### 1. Node.js & Deno Runtime Engines
| Section | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **Node.js Runtime & Libuv** | V8 engine, Libuv event loop phases, microtask queues, threadpool | Backend, SRE | [`nodejs/00_nodejs_runtime_architecture_libuv_and_event_loop.md`](nodejs/00_nodejs_runtime_architecture_libuv_and_event_loop.md) |
| **Streams & Multi-Core Scaling** | Backpressure pipelines, binary buffers, cluster forking, worker threads | High-Throughput I/O | [`nodejs/01_nodejs_streams_buffers_clustering_and_worker_threads.md`](nodejs/01_nodejs_streams_buffers_clustering_and_worker_threads.md) |
| **Deno Secure Runtime** | Rust core (rusty_v8 + Tokio), zero-permission sandbox, native TS, Deno KV | Secure Edge | [`deno/00_deno_runtime_architecture_rust_v8_and_security_model.md`](deno/00_deno_runtime_architecture_rust_v8_and_security_model.md) |

### 2. JavaScript & TypeScript Full-Stack Engineering
| Section | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **Frontend JavaScript & Web APIs** | Critical rendering path, DOM/CSSOM, event loop, Service Workers, PWA | Frontend, Web Perf | [`javascript_frontend/00_browser_javascript_dom_event_loop_and_web_apis.md`](javascript_frontend/00_browser_javascript_dom_event_loop_and_web_apis.md) |
| **Backend JavaScript & APIs** | Clean layered architecture, Fastify vs Express, database ORMs, REST/GraphQL | API Arch, Microservices | [`javascript_backend/00_backend_javascript_microservices_rest_and_architecture.md`](javascript_backend/00_backend_javascript_microservices_rest_and_architecture.md) |
| **TypeScript Advanced Type System** | Structural typing, Generics, Conditional Types, `infer`, Template Literals, AST | Type Safety, Architecture | [`typescript/00_typescript_type_system_generics_and_compiler_ast.md`](typescript/00_typescript_type_system_generics_and_compiler_ast.md) |

### 3. Modern Frontend Frameworks
| Section | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **React Fiber & Hooks** | Double-buffering reconciliation, Virtual DOM diffing, Concurrent Mode, Transitions | UI Engineering | [`react/00_react_fiber_architecture_virtual_dom_and_hooks.md`](react/00_react_fiber_architecture_virtual_dom_and_hooks.md) |
| **Next.js App Router & RSC** | React Server Components, Server Actions, 4-tier caching, Turbopack, Edge runtime | Full-Stack, SSR | [`nextjs/00_nextjs_app_router_server_components_and_edge_runtime.md`](nextjs/00_nextjs_app_router_server_components_and_edge_runtime.md) |
| **Vue 3 Reactivity & Pinia** | Proxy dependency tracking (`track`/`trigger`), Composition API, Block Tree optimization | UI Frameworks | [`vue/00_vue_reactivity_proxy_system_composition_api_and_pinia.md`](vue/00_vue_reactivity_proxy_system_composition_api_and_pinia.md) |
| **Angular Signals & Ivy** | Fine-grained push-pull Signals, Ivy compiler, Standalone Components, RxJS | Enterprise Web | [`angular/00_angular_signals_ivy_compiler_and_standalone_architecture.md`](angular/00_angular_signals_ivy_compiler_and_standalone_architecture.md) |

### 4. Dart & Flutter Cross-Platform Ecosystem
| Section | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **Dart Language & VM Isolates** | Sound Null Safety, JIT vs AOT compilation, Isolate memory heaps, async streams | Language Internals | [`dart/00_dart_language_architecture_vm_isolates_and_aot.md`](dart/00_dart_language_architecture_vm_isolates_and_aot.md) |
| **Flutter for Web & WasmGC** | CanvasKit Skia WebGL, WebAssembly GC (WasmGC) compilation, responsive layouts | Web Apps, Wasm | [`flutter_web/00_flutter_web_architecture_canvaskit_and_wasm_gc.md`](flutter_web/00_flutter_web_architecture_canvaskit_and_wasm_gc.md) |
| **Flutter for Mobile & Impeller** | Three-Tree hierarchy, Impeller Metal/Vulkan shaders, Platform Channels, Riverpod | Mobile iOS/Android | [`flutter_mobile/00_flutter_mobile_architecture_impeller_and_platform_channels.md`](flutter_mobile/00_flutter_mobile_architecture_impeller_and_platform_channels.md) |
| **Dart for Real-World Apps** | Full-stack Dart with Serverpod (Postgres ORM, WebSockets), Dart Frog microservices | Full-Stack Cloud | [`dart_real_world/00_full_stack_dart_serverpod_microservices_and_production.md`](dart_real_world/00_full_stack_dart_serverpod_microservices_and_production.md) |

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
2. **Technical Deep Dives**: Comprehensive architecture explanations, runtime internals, and execution mechanics.
3. **Hands-On Step-by-Step Walkthroughs**: Reproducible labs for developing, compiling, and testing production applications.
4. **Clean, Escaped CLI Snippets**: Formatted with trailing ` \` line escapes, 4-space indentation, and zero in-code comments.
5. **Trustworthy Curated Sources**: Exactly 5 official documentation links + 5 authoritative engineering blogs per module.
6. **FinOps & Resource Governance**: 500+ word guidelines on compute right-sizing, memory optimization, and cloud cost reduction.