# Module 12: High Availability with Keepalived, VRRP & Active-Passive Failover

**Track:** Enterprise NGINX  
**Category:** High Availability & Failover Architecture

---

## The Single Point of Failure Problem

A single NGINX instance, no matter how well configured, is a single point of failure. If the host machine loses power, the process crashes, or the NIC fails, all traffic stops. For systems requiring 99.99% uptime (~52 minutes downtime/year), one NGINX server is not acceptable.

High availability for NGINX requires at minimum **two NGINX servers** with a mechanism for one to take over automatically when the other fails. The standard Linux solution is **Keepalived** using **VRRP** (Virtual Router Redundancy Protocol), which provides a **Virtual IP address** (VIP) that floats between the two servers.

---

## How VRRP and Virtual IPs Work

In a VRRP pair, one server is **Master** and the other is **Backup**. Both servers run NGINX. A **Virtual IP address** — an additional IP configured in software — is held by the Master.

All DNS records for your service point to the VIP. Clients connect to the VIP. The VIP lives on whichever server is currently Master.

```
Normal operation:
  DNS: api.example.com → 10.0.0.100 (VIP)

  Server A (Master, 10.0.0.10)
  ├── owns VIP 10.0.0.100
  ├── NGINX serving traffic
  └── Sends VRRP advertisements every second

  Server B (Backup, 10.0.0.11)
  ├── does NOT own VIP
  ├── NGINX running (ready)
  └── Listening for VRRP advertisements

Failure — Server A goes down:
  Server B detects: no VRRP advertisement for 3 seconds
  Server B claims: takes VIP 10.0.0.100 via gratuitous ARP
  Server B becomes Master, serves all traffic

Recovery — Server A comes back:
  Server A sends VRRP advertisement with higher priority
  Server A reclaims VIP (preempt mode)
  Server B returns to Backup role
```

Failover typically completes in **2-4 seconds** (VRRP advertisement interval × dead interval).

---

## Installing and Configuring Keepalived

```bash
# Install Keepalived on both servers
apt-get install -y keepalived

# Ensure NGINX is installed and running on both servers
systemctl enable nginx
systemctl start nginx
```

### Keepalived Configuration — Master Node (Server A)

```ini
# /etc/keepalived/keepalived.conf  (Server A — Master)

global_defs {
    router_id NGINX_MASTER     # Unique identifier for this node
    enable_script_security     # Required to run custom scripts safely
}

# Health check script: is NGINX responding?
vrrp_script check_nginx {
    script "/usr/bin/curl -sf http://127.0.0.1/health"
    interval 2      # Run every 2 seconds
    weight   -20    # If check fails: reduce this node's priority by 20
    rise     2      # Require 2 successes before marking healthy
    fall     3      # Require 3 failures before marking unhealthy
}

vrrp_instance VI_1 {
    state  MASTER                    # This is the initial Master
    interface eth0                   # Network interface holding the VIP
    virtual_router_id 51             # Must match on both nodes (1-255)
    priority 110                     # Master has higher priority than Backup

    # Send advertisement every 1 second
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass S3cr3tP@ssw0rd    # Must match on both nodes
    }

    # The Virtual IP address that floats between servers
    virtual_ipaddress {
        10.0.0.100/24 dev eth0      # VIP with subnet mask
    }

    # Run the NGINX health check
    track_script {
        check_nginx
    }

    # Execute scripts on state transitions
    notify_master   "/etc/keepalived/notify.sh MASTER"
    notify_backup   "/etc/keepalived/notify.sh BACKUP"
    notify_fault    "/etc/keepalived/notify.sh FAULT"
}
```

### Keepalived Configuration — Backup Node (Server B)

```ini
# /etc/keepalived/keepalived.conf  (Server B — Backup)

global_defs {
    router_id NGINX_BACKUP
    enable_script_security
}

vrrp_script check_nginx {
    script "/usr/bin/curl -sf http://127.0.0.1/health"
    interval 2
    weight   -20
    rise     2
    fall     3
}

vrrp_instance VI_1 {
    state  BACKUP                    # Initial state is Backup
    interface eth0
    virtual_router_id 51             # Must match Master
    priority 90                      # Lower than Master's 110

    advert_int 1

    authentication {
        auth_type PASS
        auth_pass S3cr3tP@ssw0rd    # Must match Master
    }

    virtual_ipaddress {
        10.0.0.100/24 dev eth0
    }

    track_script {
        check_nginx
    }

    notify_master   "/etc/keepalived/notify.sh MASTER"
    notify_backup   "/etc/keepalived/notify.sh BACKUP"
    notify_fault    "/etc/keepalived/notify.sh FAULT"
}
```

### Notification Script

```bash
# /etc/keepalived/notify.sh
#!/bin/bash

STATE=$1
DATE=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

case $STATE in
    MASTER)
        echo "$DATE $HOSTNAME transitioned to MASTER" >> /var/log/keepalived-state.log
        # Optional: send alert to PagerDuty, Slack, etc.
        ;;
    BACKUP)
        echo "$DATE $HOSTNAME transitioned to BACKUP" >> /var/log/keepalived-state.log
        ;;
    FAULT)
        echo "$DATE $HOSTNAME entered FAULT state" >> /var/log/keepalived-state.log
        ;;
esac
```

---

## NGINX Health Check Endpoint

The Keepalived `vrrp_script` checks `http://127.0.0.1/health`. NGINX must serve this endpoint:

```nginx
server {
    listen 80;
    server_name _;

    location /health {
        return 200 "healthy\n";
        add_header Content-Type text/plain;
        access_log off;
    }

    location / {
        # Main site configuration
        proxy_pass http://backend;
    }
}
```

The health check script in Keepalived returns a non-zero exit code if the HTTP request fails (curl `-f` flag makes curl exit with code 22 on non-2xx responses). This causes the `weight -20` penalty to drop Server A's effective priority below Server B's, triggering failover.

---

## Active-Active Configuration with Two VIPs

Two servers each acting as both Master and Backup for different VIPs, sharing load during normal operation:

```
Server A: Master for VIP1 (10.0.0.100), Backup for VIP2 (10.0.0.101)
Server B: Master for VIP2 (10.0.0.101), Backup for VIP1 (10.0.0.100)

DNS round-robin: api.example.com → 10.0.0.100, 10.0.0.101

If Server A fails: Server B takes over both VIPs (handles all traffic alone)
If Server B fails: Server A takes over both VIPs
```

This requires two `vrrp_instance` blocks on each server with different `virtual_router_id` values and crossed Master/Backup states.

---

## CLI: Managing and Monitoring Keepalived

```bash
# Start Keepalived on both servers
systemctl start keepalived
systemctl enable keepalived

# Check current VRRP state (should show MASTER or BACKUP)
journalctl -u keepalived -n 50

# Verify VIP is present on current Master
ip addr show eth0 | grep "10.0.0.100"

# Simulate failover: stop Keepalived on Master
systemctl stop keepalived

# On Backup server — verify it has claimed the VIP
ip addr show eth0 | grep "10.0.0.100"

# Test failover from client perspective
watch -n 0.5 'curl -s --connect-timeout 1 http://10.0.0.100/health'

# Check Keepalived state transitions log
tail -f /var/log/keepalived-state.log

# Measure failover time (from the watch output above)
# Typically 2-4 seconds for advertisement interval=1, fail threshold=3
```

---

## Firewall Rules for VRRP

VRRP uses IP protocol 112 (not TCP or UDP). If you use `ufw` or `iptables`, you must permit it:

```bash
# Allow VRRP protocol (IP protocol 112) between the two servers
ufw allow proto vrrp

# Or with iptables directly
iptables -A INPUT  -p 112 -j ACCEPT
iptables -A OUTPUT -p 112 -j ACCEPT

# VRRP advertisements are sent to multicast address 224.0.0.18
# Some environments require allowing this specific multicast group
iptables -A INPUT -d 224.0.0.18 -j ACCEPT
```

---

## FinOps: HA Without Managed Load Balancers

AWS Elastic Load Balancer provides high availability automatically at $0.008/LCU-hour plus instance fees. For a two-instance NGINX HA pair with Keepalived, the only cost is two EC2 instances. Eliminating one ALB that handles 100 LCUs continuously saves approximately $58/month. At scale with multiple HA pairs across environments, savings compound.

The Keepalived failover time of 2-4 seconds means SLA availability is approximately 99.999% per failover event — comparable to managed load balancers with faster failover (sub-second), but sufficient for most applications that handle brief connection resets gracefully.

---

## Troubleshooting

**Both servers become MASTER at the same time (split-brain)**

Cause: VRRP advertisements are not reaching the Backup, usually due to a misconfigured firewall blocking VRRP (IP protocol 112) or multicast traffic.

Fix: Verify VRRP traffic passes between servers:
```bash
# On Backup server, capture VRRP packets from Master
tcpdump -i eth0 proto 112
```
If no packets appear, the firewall is blocking them.

**VIP not assigned even though Keepalived shows MASTER**

The `virtual_router_id` may mismatch between the two configuration files, or `interface` may name the wrong network interface. Verify:
```bash
ip link show         # Lists all interfaces
cat /proc/net/dev    # Shows interface names
```

**Failover happens but service is still unreachable for 30+ seconds**

ARP cache on routers and switches is holding the old MAC address for the VIP. The gratuitous ARP sent by Keepalived should clear this in 1-2 seconds on most networks. If your network uses static ARP tables or unusual ARP caching policies, contact your network team to reduce ARP cache TTLs.
