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

## Creating a Virtual Host

## NGINX Location Contents

## NGINX Variables

## NGINX Rewrites and Returns

## NGINX Try Files

## NGINX Logs

## NGINX Inherentance and directives

## PHP Processing

## NGINX Worker Processes

## NGINX Buffers and Timeouts

## NGINX Modules