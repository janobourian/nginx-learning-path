# Security

## HTTPS (SSL)

* http is an insecure protocol
* https is a secure connections
* ports:
    * 21: FTP
    * 22: SSH
    * 22: SFTP
    * 80: HTTP
    * 443: HTTPS

```sh
events {}

http {
    server {
        listen 80;
        server_name <DOMAIN>;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name <DOMAIN>;
        root /sites/demo;
        index index.html;

        ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
        
        # Disable SSL
        ssl_protocols TLSv1.2 TLSv1.3;
        # Optimise cipher suits
        ssl_prefer_server_ciphers on;
        ssl_ciphers HIGH:!aNULL:!MD5;
        # Enable DH Params
        ssl_dhparam /etc/nginx/ssl/dhparam.pem;
        # Enable HSTS
        add_header Strict-Transport-Security "max-age-3153600" always;
        # SSL sessions
        ssl_session_cache shared:SSL:40m;
        ssl_session_timeout 4h;
        ssl_session_tickets on;

        location / {
            try_files $uri $uri/ =404;
        }   
    }
}
```

## Rate Limiting

* Managing incoming requests
* Reasons:
    * Security - Brute Force Protection
    * Reliability - Prevent Traffic Spikes
    * Shaping - Service Priority
* `Siege` is a tool to measure the traffic
    * Load Testing Tool
* 1r/s + 5 burts = 6 connections

## Basic Auth

* First we need a password `htpasswd -c /etc/nginx/.htpasswd user1` 
* Now you should add the password
    * `auth_basic "Secure Area";`
    * `auth_basic_user_file /etc/nginx/.htpasswd;`

## Hardering NGINX

* You can remove the nginx version from the response after `cUrl` request
* You can prevent to embed your website in other webpages using `iframe` html tag
    * `add_header X-Frame-Options "SAMEORIGIN";`
    * `add_header X-XSS-Protection "1; mode=block";`
* Remove unused and potential risk modules

## Let's Encrypt - SSL Certificates

* You can use the indicated tools on the `production` section on this documentation  