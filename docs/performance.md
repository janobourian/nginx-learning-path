# Performance

## Headers and Expires

* How long the browser cache the information or resources

```sh
user nginx;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include mime.types;

    server {
        listen 80;
        server_name api.development.janobourian.com.mx;
        return 301 return 301 https://$host$request_uri;
    }

    server {
        listen 443;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        try_files $uri $uri/ @404;

        location @404 {
            access_log /var/log/nginx/404.access.log;
            return 404 'Sorry, this page or file does not exist.';
        }

        location = /api/health {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 '{"status": "ok"}';
        }

        location ~* \.(css|js|jpg|png)$ {
            access_log off;
            add_header Cache-Control public;
            add_header Pragma public;
            add_header Vary Accept-Encoding;
            expires 1M;
        }
    }
}
```

## Compressed Responses with gzip

* To compress the response to reduce the response.

```sh
user nginx;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    gzip on;
    gzip_com_level 3;
    gzip_types text/css;
    gzip_types text/javascript;

    server {
        listen 80;
        server_name api.development.janobourian.com.mx;
        return 301 return 301 https://$host$request_uri;
    }

    server {
        listen 443;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        try_files $uri $uri/ @404;

        location @404 {
            access_log /var/log/nginx/404.access.log;
            return 404 'Sorry, this page or file does not exist.';
        }

        location = /api/health {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 '{"status": "ok"}';
        }

        location ~* \.(css|js|jpg|png)$ {
            access_log off;
            add_header Cache-Control public;
            add_header Pragma public;
            add_header Vary Accept-Encoding;
            expires 1M;
        }
    }
}
```

## FastCGI Cache

## HTTP2

## Server Push