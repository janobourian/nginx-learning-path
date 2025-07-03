# Reverse Proxy and Load Balancing

## Reverse proxy 

* Act as resource between the client and the server
* Interpret the client request and push it to the php server (for example)
* Parsing custom headers

## Load Balancer

* Distribuite or redirect the load
* Provide redundance
* The module for load balancer is `ngx_http_upstream_module`
* Round Robin: The next in the queue is the next server
* Sticky Sessions: `ip hash;`
* You can not reach and active server `least_conn;`

```sh
events {}

http {
    upstream php_servers{
        ip_hash;
        server localhost:10001;
        server localhost:10002;
        server localhost:10003;
    }

    server {
        listen 8888;

        location / {
            proxy_pass http://php_servers;
        }
    }
}
```
