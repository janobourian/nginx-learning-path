# Go to Production

## Pre-requirements

* Buy a custom domain using some service like GoDaddy, Hostinger, and so on. 
* Create the Public Hosted Zone on Route53
* Connect Route53 with your current domain provider.
* Create an EC2 instance using Amazon Linux 2023
* Request a Public Elastic IP
* Connect the instance IP with the Public Elastic IP
* Connect the subdomain on Route53 with our current Public Elastic IP

## The SSL process

### Configure the certonly process

```sh
sudo su
dnf check-update
dnf install certbot
certbot certonly
```

### Install and configure Nginx

```sh
dnf update -y
dnf install -y nginx
```

The encrypt files are:
* `/etc/letsencrypt/live/<DOMAIN>/fullchain.pem`
* `/etc/letsencrypt/live/<DOMAIN>/privkey.pem`

### Update the corresponding files

#### General config /etc/nginx/nginx.conf

Steps to configure

```sh
rm -f /etc/nginx/nginx.conf
nano /etc/nginx/nginx.conf
nginx -t
systemctl status nginx
systemctl enable nginx
systemctl start nginx
```

The *.conf file for this configuration

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
        index index.html;

        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        location / {
            try_files $uri $uri/ =404;
        }   

    }
}

```

#### Specific config /etc/nginx/conf.d/*.conf

In some cases we need to configure a specific file for specific domain. 

```sh
rm -f /etc/nginx/conf.d/<DOMAIN>.conf
nano /etc/nginx/conf.d/<DOMAIN>.conf
nginx -t
systemctl enable nginx
systemctl start nginx
```

The configuration inside that file should have only `server` context.

For `/etc/nginx/nginx.conf`

```sh
user nginx;
worker_processes auto;

events {
    worker_connections 65535;
}

http {
    include       mime.types;
    include /etc/nginx/conf.d/*.conf;
}
```

For `/etc/nginx/conf.d/<DOMAIN>.conf`

```sh
server {
    listen 80;
    server_name <DOMAIN>;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name <DOMAIN>;
    root /sites/demo;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files $uri $uri/ =404;
    }   

}
```