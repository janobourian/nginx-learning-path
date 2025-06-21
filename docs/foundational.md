# Foundational concepts

Exist several OS to work, specially on the Cloud. In this case I am going to use AMI Linux 2023, it uses `dnf` instead of `apt-get` like Ubunto or `yum` like CentOS.

## NGINX Configuration

We can configure NGINX fast using `dnf install -y nginx` but, to deep dive into the NGINX details we can configure using the source code. 

```sh
sudo su
dnf check-update
wget https://nginx.org/download/nginx-1.28.0.tar.gz
ls -l
tar -zxvf nginx-1.28.0.tar.gz
cd nginx-1.28.0
dnf install -y gcc gcc-c++ make automake autoconf libtool
./configure
```

The `./configure` command will fail because we do not have all packages.

```sh
dnf install -y pcre pcre-devel zlib zlib-devel openssl openssl-devel
./configure
```

If you want to know all available commands

```sh
./configure --help
```

To config nginx

You can check the documentation here: https://nginx.org/en/docs/
And you can check how builb nginx from sources: https://nginx.org/en/docs/configure.html

```sh
./configure --sbin-path=/usr/bin/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --with-pcre --pid-path=/var/run/nginx.pid --with-http_ssl_module
make
make install
ls -l /etc/nginx/
nginx -v
```

Now, to activate NGINX:

```sh
ps aux | grep nginx
nginx
ps aux | grep nginx
```

Create the systemd to manage actions like start, stop, restart, reload, start on boot using `signal`

```bash
ps aux | grep nginx
nginx -h
nginx -s stop
ps aux | grep nginx
```

If you need to stop nginx

```sh
sudo pkill -f nginx
```

### Configure the systemctl command

You should go to `/lib/systemd/system/nginx.service` and put this:

```bash
touch /lib/systemd/system/nginx.service
nano /lib/systemd/system/nginx.service
```

You should put the below script on `nginx.service`

```sh
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/bin/nginx -t
ExecStart=/usr/bin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Now you can start to use systemd

```bash
systemctl start nginx
systemctl status nginx
systemctl stop nginx
systemctl enable nginx
systemctl start nginx
systemctl reload nginx
```

## NGINX .conf File

The `nginx.conf` file has two important sections:
* context
* directive

The context refers about sections inside `{}` and the directive refers about statments like `user nginx;` or `include mime.types;`

Context example:

```bash
http {
    index index.html index.htm index.php;
    include mime.types;

    server {
        listen 80;
        server_name mydomain.com;
    }
}
```

Directive example:

```bash
user www www;
worker_processes auto;
```

## Creating a Virtual Host

You should create and edit some folder and files to contain your `html`, `css` and `js` files.

In my case I will use: 

* `ls -l /sites/demo/`: To configure the static site, maybe you will need to create the folder structure
* `ls -l /etc/nginx/nginx.conf`: To register the site configuration

About `nginx.conf` content:

```sh
events {}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
    }
}
```

After changes we will need to validate the changes and start nginx again

```bash
nginx -t
systemctl reload nginx
```

## NGINX Location Contents

* Exact Match = 
* Preferential Prefix Match ^~
* REGEX Match ~*
* Prefix Match

```sh
events {}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # Exact Match
        location = /api/health {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 '{"status": "ok"}';
        }

        # REGEX match - case sensitive
        # location ~ /greet[0-9] {

        #     return 200 'Hello from NGINX "/greet" location - REGEX MATCH';
        # }

        # REGEX match - case insensitive
        # location ~* /greet[0-9] {

        #     return 200 'Hello from NGINX "/greet" location - REGEX MATCH INSENSITIVE';
        # }

        # Prefix match
        # location /greet {

        #     return 200 'Hello from NGINX "/greet" location.';
        # }
    }
}
```

## NGINX Variables

* Nginx variables: https://nginx.org/en/docs/varindex.html

```sh
events {}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # Check static API key
        # if ( $arg_apikey != 1234 ) {
        #     return 401 "Incorrect API Key";
        # }

        # Variable
        set $weekend 'No';

        # Check if weekend
        if ( $date_local ~ 'Saturday|Sunday' ){
            set $weekend 'Yes';
        }

        location = /inspect {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 "{\"host\": \"$host\", \"uri\": \"$uri\", \"name\": \"$arg_name\", \"Date Local\": \"$date_local\", \"is_weekend\":\"$weekend\", \"args\": \"$args\"}";
        }

        # Exact Match
        location = /api/health {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 '{"status": "ok"}';
        }

        # REGEX match - case sensitive
        # location ~ /greet[0-9] {

        #     return 200 'Hello from NGINX "/greet" location - REGEX MATCH';
        # }

        # REGEX match - case insensitive
        # location ~* /greet[0-9] {

        #     return 200 'Hello from NGINX "/greet" location - REGEX MATCH INSENSITIVE';
        # }

        # Prefix match
        # location /greet {

        #     return 200 'Hello from NGINX "/greet" location.';
        # }
    }
}
```

## NGINX Rewrites and Returns

* rewrite pattern URI -> maintain your uri
    * The requests are re-evaluated
    * Some examples:
        * `rewrite ^/user/\w+ /greet;`
        * `rewrite ^/user/{\w+} /greet/$1;`
    * `last`:
        * `rewrite ^/user/{\w+} /greet/$1 last;`
        * `rewrite ^/user/{\w+} /thumb.png;`
* return status URI -> change your uri

## NGINX Try Files

* Remember that you can use `named_locations`

```sh
events {}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # try_files $uri $uri/ /404;

        # location = /404 {
        #     return 404 'Sorry, this page or file does not exist.';
        # }

        try_files $uri $uri/ @404;

        location @404 {
            return 404 'Sorry, this page or file does not exist.';
        }

        location = /api/health {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 '{"status": "ok"}';
        }
    }
}
```

## NGINX Logs

* Error Log
* Access Log
* In my case `ls -l /var/log/nginx/`
* `access_log off;`

```sh
ls -l /var/log/nginx/
cd /var/log/nginx
echo '' > access.log
echo '' > error.log
cat error.log
```

Another way to check logs

```sh
tail -n 1 /var/log/nginx/error.log
```

```sh
events {}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
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
    }
}
```

## NGINX Inherentance and directives

* Array Directive
* Standard Directive
* Action Directive

## PHP Processing

We can use php-fpm

```sh
dnf check-update
dnf install php-fpm
which php-fpm
systemctl list-unit-files | grep php
systemctl enable php-fpm
systemctl start php-fpm
systemctl status php-fpm
find / -name *www.sock
echo '<?php phpinfo(); ?>' > /sites/demo/info.php
echo '<h1> Date: <?php echo date("l jS F"); ?></h1>' > /sites/demo/index.php
```

To deal with the basic interactions `index index.php index.html;`

```sh
user nginx;
worker_processes auto;

events {
    worker_connections 65535;
}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
        root /sites/demo;
        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        index index.php index.html;

        location / {
            try_files $uri $uri/ @404;
        }

        location ~\.php$ {
            include fastcgi.conf;
            fastcgi_pass unix:/run/php-fpm/www.sock;
        }

        location @404 {
            access_log /var/log/nginx/404.access.log;
            return 404 'Sorry, this page or file does not exist.';
        }

        location = /api/health {
            default_type application/json;
            add_header Content-Type application/json;
            return 200 '{"status": "ok"}';
        }
    }
}
```

## NGINX Worker Processes

`systemctl status nginx`

* Check additional information:
    * `nproc`
    * `lscpu`
    * `ulimit -n`
* Total connections:
    * worker_processes x worker_connections = max_connections
* If you need to change you pid file
    * `pid /var/run/new_nginx.pid`

```sh
user nginx;
worker_processes auto;

events {
    worker_connections 65535;
}

http {
    include mime.types;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
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
    }
}
```

## NGINX Buffers and Timeouts

Buffering is the amount of data to save before to realese that amount.

```sh
user nginx;
worker_processes auto;

events {
    worker_connections 65535;
}

http {
    include mime.types;

    # Buffer size for POST submissions
    client_body_buffer_size 10K;
    client_max_body_size 8m;

    # Buffer size for Headers
    client_header_buffer_size 1K;

    # Max time to receive client headers/body (milliseconds)
    client_body_timeout 12;
    client_header_timeout 12;

    # Max time to keep a connection open for
    keepalive_timeout 60s;

    # Max time for the client accept/receive a response
    send_timeout 60s;

    # Skip buffering for static files
    sendfile on;

    # Optimise sendfile packets
    tcp_nopush on;

    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        server_name <DOMAIN>;
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
    }
}
```

## NGINX Modules

* Add new modules like: SSL, pagespeed
* In the folder where you started the configuration type `nginx -V` and you'll get something like this:
    * `--sbin-path=/usr/bin/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --with-pcre --pid-path=/var/run/nginx.pid --with-http_ssl_module`
* Adding the new modules (http_image_filter_module=dynamic)

```sh
./configure --help
./configure --help | grep dynamic
dnf install gd gd-devel
./configure --sbin-path=/usr/bin/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --with-pcre --pid-path=/var/run/nginx.pid --with-http_ssl_module --with-http_image_filter_module=dynamic --modules-path=/etc/nginx/modules
make
make install
```