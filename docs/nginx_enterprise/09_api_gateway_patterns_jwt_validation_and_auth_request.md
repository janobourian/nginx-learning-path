# Module 09: API Gateway Patterns, JWT Validation & `auth_request`

**Track:** Enterprise NGINX  
**Category:** API Gateway & Authentication Proxy

---

## NGINX as an API Gateway

An **API gateway** is a single entry point that all client requests pass through before reaching backend services. The gateway handles cross-cutting concerns: authentication, authorization, rate limiting, logging, and routing — so individual backend services do not have to implement these themselves.

NGINX is not a feature-complete API gateway like Kong or AWS API Gateway, but for many organizations its combination of reverse proxy, `auth_request` module, rate limiting, and Lua scripting (via OpenResty) covers the full API gateway use case at a fraction of the complexity.

The core capability that enables NGINX to act as an authentication gateway is the `ngx_http_auth_request_module`.

---

## The `auth_request` Module: How It Works

When a request arrives, NGINX makes a **subrequest** to an internal authentication endpoint before forwarding the request to the backend. If the auth endpoint returns 2xx, the request proceeds. If it returns 401 or 403, NGINX returns that status to the client immediately without touching the backend.

```
Client request → NGINX
                  ├─ Subrequest → /auth endpoint (your auth service)
                  │   ├─ Returns 200 → forward to backend
                  │   └─ Returns 401 → return 401 to client (backend never sees request)
                  └─ Proxy to backend (only if auth passed)
```

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    # ── Internal auth subrequest target ───────────────────────────────────
    location /internal/auth {
        internal;  # Only reachable via auth_request, not directly by clients

        proxy_pass http://auth_service:8080/validate;
        proxy_pass_request_body off;       # Don't forward request body to auth
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header Authorization $http_authorization;
    }

    # ── Protected API routes ───────────────────────────────────────────────
    location /api/v1/ {
        auth_request /internal/auth;

        # If auth fails, return 401 with JSON body
        error_page 401 = @unauthorized;
        error_page 403 = @forbidden;

        # Pass headers from the auth response back to the backend
        # This allows auth service to set X-User-Id, X-User-Role, etc.
        auth_request_set $auth_user_id   $upstream_http_x_user_id;
        auth_request_set $auth_user_role $upstream_http_x_user_role;

        proxy_set_header X-User-Id   $auth_user_id;
        proxy_set_header X-User-Role $auth_user_role;
        proxy_set_header Host $host;

        proxy_pass http://backend_services;
    }

    location @unauthorized {
        return 401 '{"error":"unauthorized","message":"A valid bearer token is required."}';
        add_header Content-Type application/json always;
    }

    location @forbidden {
        return 403 '{"error":"forbidden","message":"Insufficient permissions for this resource."}';
        add_header Content-Type application/json always;
    }
}
```

---

## JWT Validation at NGINX Level

NGINX Plus supports native JWT validation (`auth_jwt` directive). For open-source NGINX, you validate JWTs either in your `auth_request` service or using Lua via OpenResty.

### Option 1: JWT Validation via Auth Service (Standard NGINX)

Your `auth_service` receives the `Authorization: Bearer <token>` header, validates the JWT signature against your public key, checks expiry, and returns:
- `200` with `X-User-Id` and `X-User-Role` headers if valid
- `401` if token is missing, expired, or has invalid signature
- `403` if token is valid but the user lacks permission

This is the cleanest architectural separation: NGINX handles routing and traffic control; the auth service owns token logic.

### Option 2: JWT Validation via Lua (OpenResty)

OpenResty extends NGINX with embedded LuaJIT. You can validate JWTs inline without a subrequest round trip:

```nginx
# nginx.conf (OpenResty)
http {
    lua_shared_dict jwt_cache 10m;  # Cache validated tokens

    server {
        listen 443 ssl;

        location /api/ {
            access_by_lua_block {
                local jwt = require "resty.jwt"
                local cjson = require "cjson"

                -- Extract bearer token
                local auth_header = ngx.var.http_authorization
                if not auth_header then
                    ngx.status = ngx.HTTP_UNAUTHORIZED
                    ngx.say(cjson.encode({error = "missing_token"}))
                    ngx.exit(ngx.HTTP_UNAUTHORIZED)
                end

                local token = auth_header:match("^Bearer%s+(.+)$")
                if not token then
                    ngx.status = ngx.HTTP_UNAUTHORIZED
                    ngx.say(cjson.encode({error = "invalid_token_format"}))
                    ngx.exit(ngx.HTTP_UNAUTHORIZED)
                end

                -- Validate JWT signature with RS256 public key
                local verified = jwt:verify(
                    [[-----BEGIN PUBLIC KEY-----
                    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
                    -----END PUBLIC KEY-----]],
                    token
                )

                if not verified.verified then
                    ngx.status = ngx.HTTP_UNAUTHORIZED
                    ngx.say(cjson.encode({error = verified.reason}))
                    ngx.exit(ngx.HTTP_UNAUTHORIZED)
                end

                -- Set user context headers for backend
                ngx.req.set_header("X-User-Id", verified.payload.sub)
                ngx.req.set_header("X-User-Role", verified.payload.role)
            }

            proxy_pass http://backend;
        }
    }
}
```

---

## API Key Authentication

For machine-to-machine APIs, API keys are often preferred over JWTs because they are simpler — no expiry logic or token refresh required.

```nginx
http {
    # Load valid API keys from a file into a map
    # /etc/nginx/api_keys.conf contains: "key_value" 1;
    map $http_x_api_key $api_client_id {
        include /etc/nginx/api_keys.conf;
        default "";   # Empty string = key not found
    }
}

# /etc/nginx/api_keys.conf
"sk_live_abc123def456" "client_shopify_integration";
"sk_live_xyz789uvw012" "client_mobile_app_ios";
"sk_live_mno345pqr678" "client_data_pipeline";
```

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    location /api/ {
        # Reject if API key is unknown
        if ($api_client_id = "") {
            return 401 '{"error":"invalid_api_key"}';
        }

        # Pass client identity to backend
        proxy_set_header X-Client-Id $api_client_id;
        proxy_set_header Host $host;
        proxy_pass http://backend;
    }
}
```

API key rotation: add the new key to `api_keys.conf`, reload NGINX, then remove the old key after all clients have migrated. Zero-downtime key rotation without code deploys.

---

## Route-Based Service Routing (Microservices Gateway)

```nginx
upstream user_service    { server 10.0.0.1:3001; keepalive 32; }
upstream product_service { server 10.0.0.2:3002; keepalive 32; }
upstream order_service   { server 10.0.0.3:3003; keepalive 32; }
upstream search_service  { server 10.0.0.4:3004; keepalive 32; }

server {
    listen 443 ssl;
    server_name api.example.com;

    # Apply auth to all API routes
    location /api/ {
        auth_request /internal/auth;
        error_page 401 = @unauthorized;
    }

    location /api/v1/users {
        auth_request /internal/auth;
        proxy_pass http://user_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
    }

    location /api/v1/products {
        auth_request /internal/auth;
        proxy_pass http://product_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
    }

    location /api/v1/orders {
        auth_request /internal/auth;
        # Orders requires stricter rate limiting
        limit_req zone=order_limit burst=10 nodelay;
        proxy_pass http://order_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
    }

    # Search is public — no auth required
    location /api/v1/search {
        limit_req zone=search_limit burst=50 nodelay;
        proxy_pass http://search_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
    }
}
```

---

## CLI: Testing Auth Gateway Behavior

```bash
# Test with valid bearer token
curl -H "Authorization: Bearer eyJhbGci..." https://api.example.com/api/v1/users

# Test with missing token — should return 401
curl https://api.example.com/api/v1/users

# Test with expired token — should return 401
curl -H "Authorization: Bearer expired_token" https://api.example.com/api/v1/users

# Test API key authentication
curl -H "X-API-Key: sk_live_abc123def456" https://api.example.com/api/v1/users

# Inspect what headers the backend actually receives
curl -H "Authorization: Bearer valid_token" \
    https://api.example.com/api/debug/headers

# Monitor auth service subrequest latency
tail -f /var/log/nginx/access.log \
    | awk '{print $7, $NF}' \
    | grep internal/auth
```

---

## FinOps: Auth at the Gateway

Without NGINX auth_request, every backend microservice implements authentication independently — duplicating JWT parsing, secret management, and caching logic. At scale with 10 microservices, this means 10 auth implementations to maintain and 10 surfaces for auth bugs.

Centralizing authentication in NGINX also means auth failures short-circuit before the request reaches backend compute, saving the CPU cost of request parsing, database lookups, and response serialization on the backend. For an API endpoint receiving 50% unauthenticated/invalid requests (common with public APIs attacked by bots), this offload can reduce backend CPU by 30-50%.

---

## Troubleshooting

**`auth_request` always returns 500**

The auth subrequest itself is failing. Check that `/internal/auth` is marked `internal;` (required) and that the `proxy_pass` target is reachable. Add error logging:

```bash
tail -f /var/log/nginx/error.log | grep "auth_request"
```

**Auth passes but backend receives no X-User-Id header**

You defined `auth_request_set $auth_user_id $upstream_http_x_user_id;` but your auth service is returning the header as `X-UserId` (different capitalization). NGINX normalizes headers to lowercase internally. Check the exact header name with:

```bash
curl -I http://auth-service:8080/validate -H "Authorization: Bearer token"
```

**API key map not updating after editing api_keys.conf**

The `map` directive re-reads the included file on NGINX reload, not automatically. After editing `api_keys.conf`, run `nginx -t && nginx -s reload`.
