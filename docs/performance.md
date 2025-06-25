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

* In order to avoid server side language processes

```sh
events {}

http {
    ...
    fastcgi_cache_path /tmp/nginx_cache levels=1:2 keys_zone=ZONE_1:100m inactive=10m;
    fastcgi_cache_key "$scheme$request_method$host$request_uri";
    add_header X-Cache $upstream_cache_status;
    ...

    server {
        ...
        set $no_cache=0;
        if ( $arg_skipcache = 1 ) {
            set $no_cache 1;
        }
        ...
        location ~\.php$ {
            fastcgi_cache ZONE_1;
            fastcgi_cache_valid 200 60m;
            fastcgi_cache_valid 404 10m;
            fastcgi_cache_bypass $no_cache;
            fastcgi_no_cache $no_cache;
        }
        ...
    }
}
```

## HTTP2

* Binary Protocol
* HTTP1 was Text Protocol
* Compressed Headers
* Persistent Connections
* Multiplex Streaming
* Server Push
* HTTP2 is only avaiable with SSl

How to install

```sh
pwd
cd /home/ec2-user
ls -l
cd nginx-1.28.0
./configure --help
./configure --help | grep http_v2
./configure --sbin-path=/usr/bin/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --with-pcre --pid-path=/var/run/nginx.pid --with-http_ssl_module --with-http_image_filter_module=dynamic --with-http_v2_module --modules-path=/etc/nginx/modules
make
make install
systemctl restart nginx
```

## Server Push

* Library: https://nghttp2.org
* Example: https://www.f5.com/company/blog/nginx/nginx-1-13-9-http2-server-push

The goal is receive some files with another file, for example when `/index.html` is requested you will receive other files such as `/styles.css`

```sh
location = /index.html {
    http2_push /style.css;
    http2_push /image.png;
}
```