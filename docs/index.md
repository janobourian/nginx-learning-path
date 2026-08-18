# Enterprise Software Architecture & Web Engineering — Master Textbook Index
**Repository:** `vit/nginx-learning-path`
**Domain:** High-Performance Web Servers, Cloud Gateways, Full-Stack JavaScript/TypeScript & Cross-Platform Mobile/Web (Dart/Flutter)
**Status:** ✅ Complete Production-Grade Reference Manual

---

## 📌 Foundational Quick Notes (Original Notes)

* Common filesystem paths when running inside the `nginx` Docker container:
  * Default Web Root (`html`): `/usr/share/nginx/html`
  * Default Configuration Directory: `/etc/nginx/`
  * Virtual Hosts Directory: `/etc/nginx/conf.d/`

---

## 🌐 Full-Stack Web Development & Cross-Platform Technology Textbook Series

### 1. Node.js Enterprise Curriculum (Zero to Master)
| Module | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **00. Installation & Toolchain** | FNM/NVM version management, pnpm/npm package managers, V8 process object | Tooling, SRE | [`nodejs/00_installation_toolchains_and_node_runtime_environment.md`](nodejs/00_installation_toolchains_and_node_runtime_environment.md) |
| **01. Language Syntax & Statements** | Complete reserved words dictionary, operators (`??`, `?.`), control flow, generators | Core Grammar | [`nodejs/01_javascript_syntax_keywords_statements_and_operators.md`](nodejs/01_javascript_syntax_keywords_statements_and_operators.md) |
| **02. Filesystem & Binary Buffers** | Raw Buffer memory pooling (8KB slab allocator), POSIX file handles, atomic writes | Core I/O | [`nodejs/02_filesystem_buffers_and_binary_data.md`](nodejs/02_filesystem_buffers_and_binary_data.md) |
| **03. Streams & Backpressure** | Readable/Writable/Transform streams, `highWaterMark`, `stream.pipeline` | High-Throughput I/O | [`nodejs/03_streams_pipes_and_backpressure.md`](nodejs/03_streams_pipes_and_backpressure.md) |
| **04. Networking (HTTP/TCP/WS)** | Raw Layer 4 TCP streams (`node:net`), keepalive socket pooling, WebSockets | Network Arch | [`nodejs/04_networking_http_https_and_websockets.md`](nodejs/04_networking_http_https_and_websockets.md) |
| **05. Asynchronous Events & Promises** | `EventEmitter` execution order, `Promise.allSettled`, `AbortController` cancellation | Async Architecture | [`nodejs/05_asynchronous_patterns_promises_and_event_emitters.md`](nodejs/05_asynchronous_patterns_promises_and_event_emitters.md) |
| **06. Multi-Threading & Workers** | Master-Worker process clustering (`cluster.fork`), `SharedArrayBuffer`, `Atomics` | Multi-Core Scaling | [`nodejs/06_multi_threading_clustering_and_worker_threads.md`](nodejs/06_multi_threading_clustering_and_worker_threads.md) |
| **07. Fastify & Express REST APIs** | Radix-tree routing ($O(k)$), compiled JSON serialization, Ajv schema validation | API Architecture | [`nodejs/07_enterprise_api_development_fastify_and_express.md`](nodejs/07_enterprise_api_development_fastify_and_express.md) |
| **08. Database Integration** | PostgreSQL driver (`pg.Pool`), Drizzle ORM query builder, Prisma migrations | DB Engineering | [`nodejs/08_database_integration_prisma_drizzle_and_pg.md`](nodejs/08_database_integration_prisma_drizzle_and_pg.md) |
| **09. Security & Cryptography** | AES-256-GCM authenticated encryption, scrypt/argon2, constant-time comparison | AppSec, SOC 2 | [`nodejs/09_security_authentication_jwt_and_cryptography.md`](nodejs/09_security_authentication_jwt_and_cryptography.md) |
| **10. Testing & Profiling** | Native test runner (`node:test`), V8 heap snapshot memory leaks, Clinic.js flames | Performance, QA | [`nodejs/10_testing_debugging_and_memory_profiling.md`](nodejs/10_testing_debugging_and_memory_profiling.md) |
| **11. Production Cloud Deployment** | Multi-stage distroless Docker builds, PM2 cluster, Kubernetes `SIGTERM` shutdown | Cloud-Native SRE | [`nodejs/11_production_deployment_docker_pm2_and_kubernetes.md`](nodejs/11_production_deployment_docker_pm2_and_kubernetes.md) |
| **12. Child Processes & Subprocesses**| POSIX `execFile`/`spawn`, stream stdio, signal propagation, socket passing | OS Automation | [`nodejs/12_child_processes_and_system_command_orchestration.md`](nodejs/12_child_processes_and_system_command_orchestration.md) |
| **13. V8 Garbage Collector Internals**| Young/Old generation spaces, Scavenger semi-spaces, Mark-Sweep-Compact pauses | V8 Performance | [`nodejs/13_memory_management_v8_garbage_collector_internals.md`](nodejs/13_memory_management_v8_garbage_collector_internals.md) |

### 2. Deno Secure Engine Curriculum
| Module | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **00. Toolchain & deno.json** | Unified task runner, JSR/npm dual imports, V8 engine integration | Tooling, DevOps | [`deno/00_installation_toolchain_and_deno_cli.md`](deno/00_installation_toolchain_and_deno_cli.md) |
| **01. Security & Sandboxing** | Zero-permission sandbox, granular capability flags (`--allow-net`, `--deny-net`) | Secure Edge | [`deno/01_security_model_and_permissions_system.md`](deno/01_security_model_and_permissions_system.md) |
| **02. Native TS & Web Standards** | SWC compilation, universal `fetch`/`Request`/`Response`, W3C Web Crypto | TypeScript, Edge | [`deno/02_native_typescript_and_web_standards.md`](deno/02_native_typescript_and_web_standards.md) |
| **03. Deno KV ACID Database** | Embedded/distributed SQLite & FoundationDB, atomic multi-key transactions | Storage, Distributed | [`deno/04_deno_kv_acid_key_value_database.md`](deno/04_deno_kv_acid_key_value_database.md) |
| **04. Standalone Binaries & Deploy** | `deno compile` single executable generation, Deno Deploy multi-tenant V8 Isolates | Cloud SRE | [`deno/08_standalone_compilation_and_deno_deploy.md`](deno/08_standalone_compilation_and_deno_deploy.md) |

### 3. Frontend & Modern Web Frameworks Curriculum
| Module | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **JS Frontend DOM & Reflows** | Critical rendering path, layout thrashing avoidance, `DocumentFragment` batching | Frontend, Web Perf | [`javascript_frontend/01_the_dom_cssom_and_critical_rendering_path.md`](javascript_frontend/01_the_dom_cssom_and_critical_rendering_path.md) |
| **JS Browser Event System** | 3-phase propagation (capture, target, bubble), Event Delegation, Custom Events | Frontend Engineering | [`javascript_frontend/02_browser_event_system_and_event_delegation.md`](javascript_frontend/02_browser_event_system_and_event_delegation.md) |
| **JS Fetch API & Streams** | WHATWG fetch, AbortController cancellation, ReadableStream response body | Network Client | [`javascript_frontend/03_asynchronous_javascript_fetch_and_web_apis.md`](javascript_frontend/03_asynchronous_javascript_fetch_and_web_apis.md) |
| **JS WebSockets & SSE** | RFC 6455 binary framing, Server-Sent Events, heartbeat reconnection backoff | Real-Time Web | [`javascript_frontend/04_real_time_web_websockets_and_server_sent_events.md`](javascript_frontend/04_real_time_web_websockets_and_server_sent_events.md) |
| **Service Workers & PWAs** | Stale-While-Revalidate caching, CacheStorage API, offline web applications | PWA, Performance | [`javascript_frontend/06_service_workers_pwa_and_offline_strategies.md`](javascript_frontend/06_service_workers_pwa_and_offline_strategies.md) |
| **Backend REST & OpenAPI 3.1** | Richardson Maturity Level 3, RFC 7807 error details, Swagger schema compilation | API Architecture | [`javascript_backend/01_restful_api_design_and_openapi_specifications.md`](javascript_backend/01_restful_api_design_and_openapi_specifications.md) |
| **TypeScript Generics & infer** | Conditional types (`T extends U ? X : Y`), `infer` pattern matching, DeepReadonly | Type-Level Arch | [`typescript/01_generics_conditional_types_and_infer.md`](typescript/01_generics_conditional_types_and_infer.md) |
| **TypeScript Utility Types** | Mapped types, `Partial`, `Pick`, `Omit`, `Record`, recursive `Awaited<T>` | Type Engineering | [`typescript/02_utility_types_deep_dive.md`](typescript/02_utility_types_deep_dive.md) |
| **React Hooks & Fiber Lifecycle** | Singly-linked list hook states, `useTransition` concurrent updates, Custom Hooks | UI Architecture | [`react/01_react_hooks_lifecycle_and_custom_hooks.md`](react/01_react_hooks_lifecycle_and_custom_hooks.md) |
| **React Concurrent & Suspense** | Urgent vs transition priority queues, `useDeferredValue`, lazy bundle loading | UI Concurrency | [`react/02_concurrent_react_transitions_and_suspense.md`](react/02_concurrent_react_transitions_and_suspense.md) |
| **Next.js Server Actions & UI** | `'use server'` RPC mutations, `useOptimistic` instant updates, cache revalidation | Full-Stack SSR | [`nextjs/01_server_actions_mutations_and_optimistic_ui.md`](nextjs/01_server_actions_mutations_and_optimistic_ui.md) |
| **Next.js Edge Middleware** | Sub-millisecond V8 Isolate routing, stateless JWT verification, Geo-IP routing | Edge Architecture | [`nextjs/02_edge_middleware_and_jwt_authentication.md`](nextjs/02_edge_middleware_and_jwt_authentication.md) |
| **Vue 3 Reactivity & Proxies** | `Proxy` handlers, `ref` vs `reactive`, `track`/`trigger` DAG, custom debounced refs | UI Frameworks | [`vue/01_vue_3_reactivity_ref_reactive_and_proxies.md`](vue/01_vue_3_reactivity_ref_reactive_and_proxies.md) |
| **Vue 3 Pinia State Stores** | Modular stores, `storeToRefs`, actions, getters, localStorage persistence | State Architecture | [`vue/02_pinia_state_management_and_modular_stores.md`](vue/02_pinia_state_management_and_modular_stores.md) |
| **Angular Signals & Zoneless** | Fine-grained Push-Pull Reactive DAG, glitch-free execution, Zoneless change detection | Enterprise Web | [`angular/01_angular_signals_and_fine_grained_reactivity.md`](angular/01_angular_signals_and_fine_grained_reactivity.md) |
| **Angular RxJS Observables** | `switchMap`, `mergeMap`, `concatMap`, `exhaustMap`, `takeUntilDestroyed` | Reactive Streams | [`angular/02_rxjs_observables_and_reactive_operators.md`](angular/02_rxjs_observables_and_reactive_operators.md) |

### 4. Dart & Flutter Cross-Platform Curriculum
| Module | Core Internals & Architecture | Target Competencies | Document Link |
| :--- | :--- | :--- | :--- |
| **Dart Null Safety & Isolates** | Sound Null Safety, Sealed classes, Pattern Matching, Isolate multi-threading | Language Internals | [`dart/01_sound_null_safety_oop_and_concurrency.md`](dart/01_sound_null_safety_oop_and_concurrency.md) |
| **Dart Reactive Streams** | Single-subscription vs broadcast streams, `async* / yield`, `StreamTransformer` | Async Architecture | [`dart/02_streams_async_generators_and_transformers.md`](dart/02_streams_async_generators_and_transformers.md) |
| **Flutter Web WasmGC Engine** | Native WebAssembly GC bytecode, multithreaded Wasm Web Workers, CanvasKit WebGL | Web Performance | [`flutter_web/01_wasmgc_compilation_and_web_workers.md`](flutter_web/01_wasmgc_compilation_and_web_workers.md) |
| **Flutter Riverpod & State** | Compile-time safe dependency injection, `AsyncNotifier`, autoDispose memory recycling | Mobile iOS/Android | [`flutter_mobile/01_state_management_riverpod_and_bloc.md`](flutter_mobile/01_state_management_riverpod_and_bloc.md) |
| **Flutter Shaders & Impeller** | Custom GLSL fragment shaders, Impeller pre-compiled Metal/Vulkan shaders | GPU Graphics | [`flutter_mobile/02_custom_fragment_shaders_glsl_impeller.md`](flutter_mobile/02_custom_fragment_shaders_glsl_impeller.md) |
| **Serverpod Full-Stack Dart** | PostgreSQL ORM, WebSocket streaming, automated client SDK code generation | Full-Stack Cloud | [`dart_real_world/01_serverpod_postgres_orm_and_websockets.md`](dart_real_world/01_serverpod_postgres_orm_and_websockets.md) |
| **Dart Frog API Framework** | File-system routing, dependency injection middleware, high-speed REST APIs | Cloud Microservices | [`dart_real_world/02_dart_frog_high_speed_rest_api_server.md`](dart_real_world/02_dart_frog_high_speed_rest_api_server.md) |

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
1. **👔 Executive Summary**: Non-technical explanation of business purpose, mechanics, and value for stakeholders.
2. **Complete Syntax, Keywords & Reserved Words Dictionary**: Complete technical reference of statements, keywords, and operators.
3. **Technical Deep Dives**: Comprehensive architecture explanations, runtime internals, memory layouts, and execution mechanics.
4. **Hands-On Step-by-Step Walkthroughs**: Reproducible labs for developing, compiling, and testing production applications offline.
5. **Clean, Escaped CLI Snippets**: Formatted with trailing ` \` line escapes, 4-space indentation, and zero in-code comments.
6. **Trustworthy Curated Sources**: Exactly 5 official documentation links + 5 authoritative engineering blogs per module.
7. **FinOps & Resource Governance**: 500+ word guidelines on compute right-sizing, memory optimization, and cloud cost reduction.