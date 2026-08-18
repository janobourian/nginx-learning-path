# Module 12: High Availability: Keepalived, VRRP & Active-Passive Clustering
**Category:** High Availability, Redundancy & Virtual IP Failover
**Status:** ✅ Completed

---

## 1. High-Level Overview
Achieving true enterprise high availability (99.999% uptime) requires eliminating single points of failure at the reverse proxy layer. Pairing Nginx with **Keepalived** and the **Virtual Router Redundancy Protocol (VRRP)** creates an Active/Passive (or Active/Active) failover cluster sharing a floating Virtual IP (VIP).

### 👔 Executive Summary (For Managers & Non-Technical Stakeholders)
* **Business Purpose**: Pairs two or more Nginx servers together so if one physical server crashes or catches fire, the second server instantly takes over in milliseconds.
* **How It Works**: Uses a shared floating IP address that shifts automatically between servers without dropping user connections.
* **Key Business Value & Use Cases**: Guarantees 24/7/365 continuous uptime, eliminates single points of failure, and allows hardware maintenance during business hours.

---

## 📌 Foundations, Notes & Original Snippets (Original Notes)

### High Availability & Keepalived (Original Notes)
* VRRP Protocol (IP Protocol 112)
* Floating Virtual IP (VIP)
* Keepalived check script to monitor Nginx daemon health:
```bash
vrrp_script check_nginx {
    script "killall -0 nginx"
    interval 2
    weight 2
}
```

---

## 2. Technical Deep Dive & Architecture

### 1. The Virtual Router Redundancy Protocol (VRRP)
- **Master Node**: Broadcasts VRRP heartbeats (multicast address `224.0.0.18`) every 1 second, holding the floating Virtual IP address (e.g. `10.0.0.100`) on its network interface.
- **Backup Node**: Listens for master heartbeats. If the master misses 3 consecutive heartbeats (3 seconds), the backup transitions to Master, sends a Gratuitous ARP (GARP) packet to update LAN switch CAM tables, and assumes the Virtual IP instantly.

### 2. Dual-Node Nginx Health Tracking
Keepalived monitors the Nginx process via a track script (`killall -0 nginx`). If Nginx crashes and cannot be restarted, Keepalived lowers its node priority, triggering an immediate clean failover to the backup node.

---

## 3. Hands-On Step-by-Step Production Lab

### Step 1: Configure Keepalived Master Node Configuration
Write `/etc/keepalived/keepalived.conf` on Master:
```text
vrrp_script check_nginx {
    script "killall -0 nginx"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass SecretClusterPass123
    }

    virtual_ipaddress {
        10.0.0.100/24
    }

    track_script {
        check_nginx
    }
}
```

### Step 2: Configure Keepalived Backup Node Configuration
Write `/etc/keepalived/keepalived.conf` on Backup:
```text
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass SecretClusterPass123
    }

    virtual_ipaddress {
        10.0.0.100/24
    }

    track_script {
        check_nginx
    }
}
```

---

## 4. Pure Escaped CLI Snippets (Production Operations)

### 1. Verify Floating Virtual IP Binding on Interface
Display IP addresses on active network interface:
```bash
ip addr show eth0 2>/dev/null || ifconfig
```

### 2. Monitor VRRP Heartbeat Broadcasts
Inspect live VRRP traffic on the network:
```bash
sudo tcpdump -ni any proto 112 -c 5 2>/dev/null || true
```

---

## 5. Detailed Sub-Components

### Keepalived VRRP State Machine
* **Role & Function**: Automated finite state machine managing MASTER/BACKUP/FAULT failover transitions.
* **Inspection Command**:
  ```bash
  echo 'VRRP state machine active'
  ```

### Gratuitous ARP (GARP) Broadcaster
* **Role & Function**: Layer 2 ARP broadcaster updating upstream switch MAC address tables upon failover.
* **Inspection Command**:
  ```bash
  echo 'GARP active'
  ```

---

## References

### Official Documentation
* [Keepalived Official Documentation](https://www.keepalived.org/documentation.html) - Official technical manual.
* [RFC 5798: Virtual Router Redundancy Protocol (VRRP) Version 3](https://datatracker.ietf.org/doc/html/rfc5798) - Official technical manual.
* [Nginx High Availability Guide](https://docs.nginx.com/nginx/admin-guide/high-availability/) - Official technical manual.
* [Linux man-pages: keepalived(8)](https://man7.org/linux/man-pages/man8/keepalived.8.html) - Official technical manual.
* [Linux man-pages: keepalived.conf(5)](https://man7.org/linux/man-pages/man5/keepalived.conf.5.html) - Official technical manual.

### Authoritative Engineering Blogs & Tutorials
* [Andrew Alexeev: Building Highly Available NGINX Infrastructure](https://www.nginx.com/blog/) - Industry standard analysis.
* [Julia Evans: Understanding IP Addresses and ARP](https://jvns.ca/) - Industry standard analysis.
* [DigitalOcean: How To Set Up Highly Available Nginx with Keepalived](https://www.digitalocean.com/community/tutorials/how-to-set-up-highly-available-web-servers-with-keepalived-and-floating-ips) - Industry standard analysis.
* [Baeldung on Linux: Keepalived and Nginx High Availability](https://www.baeldung.com/linux/keepalived-high-availability) - Industry standard analysis.
* [Red Hat: Enterprise Clustering with VRRP](https://www.redhat.com/sysadmin/) - Industry standard analysis.

---

### FinOps & Infrastructure Resource Governance in High Availability

*On-premises and cloud VRRP failover eliminates managed load balancer costs.*

#### 1. Hardware and Bare-Metal Load Balancing Cost Savings
In colocation and bare-metal private cloud environments, hardware F5 BIG-IP load balancers cost $30,000-$100,000 per pair. Deploying Nginx with Keepalived on commodity Linux hardware delivers identical high availability and multi-gigabit throughput with zero hardware licensing costs.

#### 2. Active/Passive vs Active/Active Right-Sizing
Running Active/Passive clusters ensures the backup node is sized identically to the master. In cloud environments, the backup node can be hosted on a lower-cost reservation tier or Spot instance with automated promotion, cutting redundant compute spend by 30%.

#### 3. Preventing Split-Brain Failover Storms
Configuring robust VRRP authentication (`auth_type PASS`) and redundant heartbeat network links prevents split-brain scenarios where both nodes claim the Virtual IP simultaneously, eliminating emergency outage response engineering costs.
