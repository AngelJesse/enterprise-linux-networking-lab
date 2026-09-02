# Enterprise Hybrid Cloud & DevOps Lab: Module 1 & 2 — Enterprise Linux & Corporate Networking

[🇺🇸 Read in English](README.md) | [🇪🇸 Leer en Español](README.es.md)

![Linux](https://img.shields.io/badge/OS-Ubuntu%2024.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Networking](https://img.shields.io/badge/Networking-TCP%203--Way%20Handshake%20%7C%20Routing%20%7C%20DNS-success?style=for-the-badge&logo=wireshark&logoColor=white)
![Security](https://img.shields.io/badge/Security-Ed25519%20%7C%20UFW%20%7C%20Sudoers-blue?style=for-the-badge&logo=gnubash&logoColor=white)
![Storage](https://img.shields.io/badge/Storage-LVM%20Hot--Resize-informational?style=for-the-badge&logo=linux&logoColor=white)
![Init System](https://img.shields.io/badge/Init%20System-Systemd%20%7C%20cgroups-red?style=for-the-badge&logo=linux&logoColor=white)

## 📌 Executive Summary & Business Objective

In enterprise cloud environments (Azure, AWS, Kubernetes), infrastructure stability and reliability depend directly on the resilience of the underlying Linux operating system and low-level networking primitives. Over 80% of distributed outages attributed to application bugs are actually caused by routing loops, firewall packet drops, DNS resolution timeouts, or socket state mismatches.

This project implements a hardened, multi-node enterprise Linux cluster simulating an on-premise datacenter interconnected with static routing, granular packet filtering, automated telemetry, and real-time packet-level forensic diagnostics ready for Cloud Migration (Azure) and Configuration Management (Ansible).

---

## 🏗️ Architecture Topology

```
                         CORPORATE LAB NETWORK (192.168.204.0/24)
                                            |
                +---------------------------+---------------------------+
                |                                                       |
                v                                                       v
      +--------------------+                                 +--------------------+
      |   srv-control-01   |                                 |    srv-node-01     |
      |   (Ubuntu Server)  |                                 |   (Ubuntu Server)  |
      |                    |                                 |                    |
      | IP: 192.168.204.10 | <==== Ed25519 SSH Protocol ===> | IP: 192.168.204.11 |
      | Role: Bastion/Ops  |      (Passwordless / No-Root)   | Role: Workload/Web |
      | Routing: Static    |                                 | Svc: NGINX (Port 80)
      | IP Forwarding: ON  |                                 | Telemetry: Systemd |
      | UFW: Port 22 Only  |                                 | UFW: 22, 80, 443   |
      +--------------------+                                 |      9100 (Restricted)
                                                             | LVM: Online 28GB Resize
                                                             +--------------------+
```

---

## 🛠️ Technology Stack & Engineering Decisions

| Component | Technology | Enterprise Rationale |
| :--- | :--- | :--- |
| **Operating System** | Ubuntu Server 24.04 LTS | Standard LTS distribution across cloud vendors and container runtimes. |
| **Networking Layer** | Netplan + `systemd-networkd` | Declarative YAML-based network management; deterministic across reboots. |
| **Deep Packet Inspection** | `tcpdump` + Berkeley Packet Filters (BPF) | Low-level wire diagnostic for TCP flag inspection (`[S]`, `[S.]`, `[.]`, `[P.]`, `[F.]`, `[R.]`). |
| **Domain Name System** | `bind9-dnsutils` (`dig`) + `systemd-resolved` | Granular DNS diagnosis (A, CNAME, TXT, PTR reverse lookup) and query latency benchmarking. |
| **Kernel Routing** | `iproute2` (`ip route`) + `sysctl` | Static routing policies and kernel-level IPv4 packet forwarding (`net.ipv4.ip_forward = 1`). |
| **Storage Management** | LVM2 (Logical Volume Manager) | Dynamic volume expansion and zero-downtime online filesystem resizing (`ext4`). |
| **Service Supervisor** | Systemd (PID 1) + cgroups | Process lifecycle management, automatic recovery on failure (`SIGKILL`), and CPU/RAM isolation. |
| **Security & Access** | OpenSSH + Ed25519 Elliptic Curve | High-performance asymmetric cryptography; brute-force mitigation (`PasswordAuthentication no`). |
| **Network Security** | UFW (Uncomplicated Firewall) | Stateful packet filtering with strict `Default Deny` and Source IP Whitelisting for metrics. |

---

## 🚀 Step-by-Step Implementation & Runbook

### 1. Static Network Architecture & Local DNS
* `srv-control-01`: `192.168.204.10/24` (Gateway: `192.168.204.2`)
* `srv-node-01`: `192.168.204.11/24` (Gateway: `192.168.204.2`)
* Local resolution configured via `/etc/hosts` to decouple automation scripts from hardcoded IP addresses.

### 2. Deep Packet Inspection: The TCP 3-Way Handshake
Analyzed live packet exchanges using targeted BPF filters:
```bash
sudo tcpdump -ni ens33 'tcp port 80 and host 192.168.204.10' -c 15
```
* **Phase 1: 3-Way Handshake:** `Flags [S]` (SYN) $\rightarrow$ `Flags [S.]` (SYN-ACK) $\rightarrow$ `Flags [.]` (ACK).
* **Phase 2: L7 Application Exchange:** `Flags [P.]` (`HTTP/1.1 GET /`) $\rightarrow$ `Flags [P.]` (`HTTP/1.1 200 OK`).
* **Phase 3: 4-Way Teardown:** `Flags [F.]` (FIN) $\rightarrow$ `Flags [F.]` (FIN) $\rightarrow$ `Flags [.]` (ACK).
* **Connection Refused vs Timed Out:** Documented how closed ports trigger immediate kernel `Flags [R.]` (RST-ACK) vs firewall DROP causing SYN retransmissions and timeout.

### 3. DNS Diagnostics & Cloud Validation
* Audited DNS `A` records and Anycast Round-Robin distribution via `dig google.com`.
* Evaluated Cloud domain verification records using `dig github.com TXT +short`.
* Performed reverse DNS resolution (`PTR` lookup) on `8.8.8.8` mapping to `dns.google.`.

### 4. Kernel Routing & IPv4 Packet Forwarding
* Added static corporate routes dynamically: `sudo ip route add 10.50.0.0/16 via 192.168.204.2 dev ens33`.
* Verified routing lookup cache with `ip route get 10.50.15.20`.
* Enabled persistent kernel packet forwarding for router/Kubernetes node behavior:
  ```bash
  # /etc/sysctl.d/99-ip-forward.conf
  net.ipv4.ip_forward = 1
  ```

### 5. Cryptographic SSH Hardening & Automation Sudoers
* Deployed passwordless Ed25519 keypairs between nodes.
* Enforced `/etc/ssh/sshd_config.d/99-hardening.conf` (`PasswordAuthentication no`, `PermitRootLogin no`).
* Delegated non-interactive privilege escalation in `/etc/sudoers.d/devops` (`NOPASSWD:ALL`).

### 6. Storage Elasticity & Resilient Services
* Performed online hot-resize of root logical volume from 14GB to 28GB via `lvextend -l +100%FREE ... -r`.
* Implemented telemetry service `/opt/infra-agent/agent.sh` with Systemd auto-recovery on `SIGKILL (-9)`.

---

## 🔍 Incident Simulation & Troubleshooting Log

| Incident / Symptom | Root Cause Analysis (RCA) | Engineering Solution |
| :--- | :--- | :--- |
| **`Connection refused` on HTTP port 80** | Port open in UFW but no daemon listening; kernel responded with TCP RST-ACK. | Deployed and enabled NGINX daemon (`systemctl enable --now nginx`). |
| **`WARNING: Permissions for Netplan are too open`** | File created with default `0644` mask allowing read access to unprivileged users. | Enforced strict POSIX octal permission `chmod 600 /etc/netplan/*.yaml`. |
| **`Host key verification failed` on SSH copy** | SSH client required interactive confirmation to append host fingerprint to `known_hosts`. | Explicitly validated authenticity and accepted host key into `~/.ssh/known_hosts`. |
| **`-bash: !/bin/bash: event not found`** | Interactive Bash history expansion triggered by `!` inside double-quoted string. | Migrated to non-interpolated `sudo tee /path <<'EOF'` pattern. |

---

## 📂 Repository Structure

```
enterprise-linux-networking-lab/
├── README.md               # English Documentation
├── README.es.md            # Spanish Documentation
├── .gitignore
├── configs/
│   ├── 99-hardening.conf
│   ├── 99-ip-forward.conf
│   ├── cron-infra-healthcheck
│   ├── netplan-control.yaml
│   ├── netplan-node.yaml
│   └── sudoers-devops
├── scripts/
│   ├── agent.sh
│   └── healthcheck.sh
└── systemd/
    └── infra-agent.service
```

---

## 🎯 Next Roadmap Milestone: Module 3
Advancing to **Microsoft Azure Enterprise Infrastructure**: Resource Groups, VNets, NSGs, Azure Virtual Machines, Storage Accounts, Load Balancers, and Cloud Architecture best practices.
